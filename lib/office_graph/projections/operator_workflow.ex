defmodule OfficeGraph.Projections.OperatorWorkflow do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.Audit.AuditRecord
  alias OfficeGraph.Integrations.NormalizedIntakeEvent
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Revisions.Revision
  alias OfficeGraph.Runs
  alias OfficeGraph.WorkGraph.{GraphRelationship, ReviewFinding, Signal, Task, VerificationCheck}
  alias OfficeGraph.WorkPackets.{WorkPacketRequiredCheck, WorkPacketSourceReference}

  require Ash.Query

  @graph_resource_order %{
    "signal" => 0,
    "task" => 1,
    "review_finding" => 2,
    "verification_check" => 3
  }
  @graph_resource_modules %{
    "signal" => Signal,
    "task" => Task,
    "review_finding" => ReviewFinding,
    "verification_check" => VerificationCheck
  }

  def operator_inbox(session_context) do
    with :ok <- authorize_read(session_context),
         {:ok, events} <- read_intake_events(session_context),
         {:ok, rows} <- build_intake_rows(session_context, events) do
      {:ok,
       %{
         type: "operator_inbox",
         rows: rows,
         empty?: rows == [],
         source_watermark: source_watermark(rows)
       }}
    end
  end

  def operator_workflow_item(session_context, normalized_event_id) do
    with :ok <- authorize_read(session_context),
         {:ok, event} <- read_intake_event(session_context, normalized_event_id),
         {:ok, [row]} <- build_intake_rows(session_context, [event]) do
      {:ok, row}
    end
  end

  defp authorize_read(session_context) do
    Authorization.authorize(session_context, :skeleton_read,
      organization_id: session_context.organization_id
    )
  end

  defp read_intake_events(session_context) do
    NormalizedIntakeEvent
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(authorize?: false)
  end

  defp read_intake_event(session_context, id) do
    NormalizedIntakeEvent
    |> Ash.Query.filter(
      id == ^id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:missing_normalized_intake_event, id}}
      {:ok, event} -> {:ok, event}
      {:error, error} -> {:error, error}
    end
  end

  defp build_intake_rows(_session_context, []), do: {:ok, []}

  defp build_intake_rows(session_context, events) do
    event_ids = Enum.map(events, & &1.id)

    with {:ok, proposed_changes_by_event_id} <-
           read_proposed_changes_by_event_id(session_context, event_ids),
         {:ok, applied_projections_by_event_id} <-
           applied_projections_by_event_id(session_context, events, proposed_changes_by_event_id) do
      rows =
        Enum.map(events, fn event ->
          proposed_changes = Map.get(proposed_changes_by_event_id, event.id, [])

          applied_projection =
            Map.get(applied_projections_by_event_id, event.id, empty_applied_projection())

          build_intake_row(event, proposed_changes, applied_projection)
        end)

      {:ok, rows}
    end
  end

  defp build_intake_row(event, proposed_changes, applied_projection) do
    run_links = Map.get(applied_projection, :run_links, [])

    status = intake_status(event, proposed_changes, applied_projection.graph_links, run_links)
    reason_codes = intake_reason_codes(event, proposed_changes)
    graph_links = applied_projection.graph_links ++ run_links

    %{
      type: "operator_workflow_item",
      typed_id: %{type: "normalized_intake_event", id: event.id},
      normalized_event_id: event.id,
      duplicate_of_id: event.duplicate_of_id,
      status: status,
      reason_codes: reason_codes,
      source: %{
        identity: event.source_identity,
        replay_identity: event.replay_identity,
        outcome: event.outcome
      },
      proposed_change_status: proposed_change_status(proposed_changes),
      blocker_reasons: blocker_reasons(status, reason_codes),
      allowed_next_actions: allowed_next_actions(status),
      operation_watermark: event.operation_id,
      source_watermark: event.operation_id,
      graph_links: graph_links,
      graph_relationships: applied_projection.graph_relationships,
      audit_trace: applied_projection.audit_trace,
      revision_trace: applied_projection.revision_trace
    }
  end

  defp read_proposed_changes_by_event_id(_session_context, []), do: {:ok, %{}}

  defp read_proposed_changes_by_event_id(session_context, event_ids) do
    ProposedGraphChange
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and normalized_event_id in ^event_ids
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, proposed_changes} -> {:ok, Enum.group_by(proposed_changes, & &1.normalized_event_id)}
      {:error, error} -> {:error, error}
    end
  end

  defp applied_projections_by_event_id(session_context, events, proposed_changes_by_event_id) do
    operation_id_by_event_id =
      Map.new(events, fn event ->
        {event.id, applied_operation_id(Map.get(proposed_changes_by_event_id, event.id, []))}
      end)

    operation_ids =
      operation_id_by_event_id
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    with {:ok, audit_records_by_operation_id} <- read_audit_records_by_operation_id(operation_ids),
         {:ok, revision_records_by_operation_id} <-
           read_revision_records_by_operation_id(operation_ids),
         {:ok, graph_links_by_operation_id} <-
           graph_links_by_operation_id(session_context, audit_records_by_operation_id),
         all_graph_links = flatten_map_values(graph_links_by_operation_id),
         {:ok, graph_relationships} <- graph_relationships_for_links(all_graph_links),
         {:ok, run_links_by_operation_id} <-
           run_links_by_operation_id(session_context, graph_links_by_operation_id) do
      projections =
        Map.new(operation_id_by_event_id, fn
          {event_id, nil} ->
            {event_id, empty_applied_projection()}

          {event_id, operation_id} ->
            graph_links = Map.get(graph_links_by_operation_id, operation_id, [])

            {event_id,
             %{
               graph_links: graph_links,
               graph_relationships: relationships_for_links(graph_relationships, graph_links),
               audit_trace:
                 trace_summary(
                   operation_id,
                   Map.get(audit_records_by_operation_id, operation_id, [])
                 ),
               revision_trace:
                 trace_summary(
                   operation_id,
                   Map.get(revision_records_by_operation_id, operation_id, [])
                 ),
               run_links: Map.get(run_links_by_operation_id, operation_id, [])
             }}
        end)

      {:ok, projections}
    end
  end

  defp empty_applied_projection do
    %{
      graph_links: [],
      graph_relationships: [],
      audit_trace: %{operation_id: nil, resource_count: 0, resources: []},
      revision_trace: %{operation_id: nil, resource_count: 0, resources: []},
      run_links: []
    }
  end

  defp applied_operation_id(proposed_changes) do
    proposed_changes
    |> Enum.map(& &1.applied_operation_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [operation_id] -> operation_id
      _none_or_mixed -> nil
    end
  end

  defp read_audit_records_by_operation_id([]), do: {:ok, %{}}

  defp read_audit_records_by_operation_id(operation_ids) do
    AuditRecord
    |> Ash.Query.filter(operation_id in ^operation_ids)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, audit_records} -> {:ok, Enum.group_by(audit_records, & &1.operation_id)}
      {:error, error} -> {:error, error}
    end
  end

  defp read_revision_records_by_operation_id([]), do: {:ok, %{}}

  defp read_revision_records_by_operation_id(operation_ids) do
    Revision
    |> Ash.Query.filter(operation_id in ^operation_ids)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, revision_records} -> {:ok, Enum.group_by(revision_records, & &1.operation_id)}
      {:error, error} -> {:error, error}
    end
  end

  defp graph_links_by_operation_id(session_context, audit_records_by_operation_id) do
    audit_records =
      audit_records_by_operation_id
      |> flatten_map_values()
      |> Enum.filter(&Map.has_key?(@graph_resource_order, &1.resource_type))

    resource_ids_by_type =
      audit_records
      |> Enum.group_by(& &1.resource_type, & &1.resource_id)
      |> Map.new(fn {type, ids} -> {type, Enum.uniq(ids)} end)

    with {:ok, resources_by_type} <-
           read_graph_resources_by_type(session_context, resource_ids_by_type) do
      links_by_operation_id =
        Map.new(audit_records_by_operation_id, fn {operation_id, operation_audit_records} ->
          links =
            operation_audit_records
            |> Enum.filter(&Map.has_key?(@graph_resource_order, &1.resource_type))
            |> Enum.sort_by(&Map.fetch!(@graph_resource_order, &1.resource_type))
            |> Enum.map(&graph_link_for_loaded_resource(resources_by_type, &1))
            |> Enum.reject(&is_nil/1)

          {operation_id, links}
        end)

      {:ok, links_by_operation_id}
    end
  end

  defp read_graph_resources_by_type(session_context, resource_ids_by_type) do
    Enum.reduce_while(resource_ids_by_type, {:ok, %{}}, fn {type, ids}, {:ok, acc} ->
      resource = Map.fetch!(@graph_resource_modules, type)

      case read_scoped_many(resource, session_context, ids) do
        {:ok, records} -> {:cont, {:ok, Map.put(acc, type, Map.new(records, &{&1.id, &1}))}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp graph_link_for_loaded_resource(resources_by_type, audit_record) do
    resources_by_type
    |> Map.get(audit_record.resource_type, %{})
    |> Map.get(audit_record.resource_id)
    |> case do
      nil -> nil
      record -> graph_link(audit_record.resource_type, record)
    end
  end

  defp graph_link(type, record) do
    %{
      type: type,
      id: record.id,
      graph_item_id: record.graph_item_id,
      title: record.title,
      state: Map.get(record, :state) || Map.get(record, :lifecycle_state)
    }
  end

  defp graph_relationships_for_links([]), do: {:ok, []}

  defp graph_relationships_for_links(graph_links) do
    graph_item_ids =
      graph_links
      |> Enum.map(& &1.graph_item_id)
      |> Enum.reject(&is_nil/1)

    GraphRelationship
    |> Ash.Query.filter(source_item_id in ^graph_item_ids and target_item_id in ^graph_item_ids)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, relationships} ->
        {:ok,
         Enum.map(relationships, fn relationship ->
           %{
             id: relationship.id,
             source_graph_item_id: relationship.source_item_id,
             target_graph_item_id: relationship.target_item_id,
             relationship_type: relationship.relationship_type
           }
         end)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp relationships_for_links([], _graph_links), do: []
  defp relationships_for_links(_relationships, []), do: []

  defp relationships_for_links(relationships, graph_links) do
    graph_item_ids =
      graph_links
      |> Enum.map(& &1.graph_item_id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.filter(relationships, fn relationship ->
      MapSet.member?(graph_item_ids, relationship.source_graph_item_id) and
        MapSet.member?(graph_item_ids, relationship.target_graph_item_id)
    end)
  end

  defp run_links_by_operation_id(session_context, graph_links_by_operation_id) do
    graph_links = flatten_map_values(graph_links_by_operation_id)

    verification_check_ids =
      graph_links
      |> Enum.filter(&(&1.type == "verification_check"))
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    source_graph_item_ids =
      graph_links
      |> Enum.map(& &1.graph_item_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    with {:ok, check_links} <-
           read_work_packet_required_checks(session_context, verification_check_ids),
         {:ok, source_links} <-
           read_work_packet_source_references(session_context, source_graph_item_ids),
         version_ids_by_operation_id =
           version_ids_by_operation_id(graph_links_by_operation_id, check_links, source_links),
         version_ids = version_ids_by_operation_id |> flatten_map_values() |> Enum.uniq(),
         {:ok, runs} <- read_runs_for_versions(session_context, version_ids) do
      run_links_by_operation_id =
        Map.new(version_ids_by_operation_id, fn {operation_id, operation_version_ids} ->
          version_ids = MapSet.new(operation_version_ids)

          run_links =
            runs
            |> Enum.filter(&MapSet.member?(version_ids, &1.work_packet_version_id))
            |> Enum.map(&run_graph_link/1)

          {operation_id, run_links}
        end)

      {:ok, run_links_by_operation_id}
    end
  end

  defp read_work_packet_required_checks(_session_context, []), do: {:ok, []}

  defp read_work_packet_required_checks(session_context, verification_check_ids) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(
      verification_check_id in ^verification_check_ids and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_work_packet_source_references(_session_context, []), do: {:ok, []}

  defp read_work_packet_source_references(session_context, source_graph_item_ids) do
    WorkPacketSourceReference
    |> Ash.Query.filter(
      graph_item_id in ^source_graph_item_ids and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp version_ids_by_operation_id(graph_links_by_operation_id, check_links, source_links) do
    check_version_ids_by_check_id =
      Enum.group_by(check_links, & &1.verification_check_id, & &1.work_packet_version_id)

    source_version_ids_by_graph_item_id =
      Enum.group_by(source_links, & &1.graph_item_id, & &1.work_packet_version_id)

    Map.new(graph_links_by_operation_id, fn {operation_id, graph_links} ->
      verification_check_ids =
        graph_links
        |> Enum.filter(&(&1.type == "verification_check"))
        |> Enum.map(& &1.id)

      source_graph_item_ids =
        graph_links
        |> Enum.map(& &1.graph_item_id)
        |> Enum.reject(&is_nil/1)

      check_version_ids =
        flat_map_lookup(check_version_ids_by_check_id, verification_check_ids)

      source_version_ids =
        flat_map_lookup(source_version_ids_by_graph_item_id, source_graph_item_ids)

      {operation_id, version_intersection(check_version_ids, source_version_ids)}
    end)
  end

  defp version_intersection([], _source_version_ids), do: []
  defp version_intersection(_check_version_ids, []), do: []

  defp version_intersection(check_version_ids, source_version_ids) do
    source_version_ids = MapSet.new(source_version_ids)

    check_version_ids
    |> Enum.filter(&MapSet.member?(source_version_ids, &1))
    |> Enum.uniq()
  end

  defp read_runs_for_versions(_session_context, []), do: {:ok, []}

  defp read_runs_for_versions(session_context, version_ids) do
    Runs.Run
    |> Ash.Query.filter(
      work_packet_version_id in ^version_ids and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(authorize?: false)
  end

  defp flatten_map_values(map) do
    map
    |> Map.values()
    |> List.flatten()
  end

  defp flat_map_lookup(map, keys) do
    keys
    |> Enum.flat_map(&Map.get(map, &1, []))
    |> Enum.uniq()
  end

  defp run_graph_link(run) do
    %{
      type: "work_run",
      id: run.id,
      graph_item_id: nil,
      title: run.objective || "Work run",
      state: run.aggregate_state || run.state
    }
  end

  defp trace_summary(operation_id, trace_records) do
    %{
      operation_id: operation_id,
      resource_count: length(trace_records),
      resources:
        Enum.map(trace_records, fn record ->
          %{type: record.resource_type, id: record.resource_id}
        end)
    }
  end

  defp intake_status(%{outcome: "duplicate"}, _proposed_changes, _graph_links, _run_links),
    do: "not_actionable"

  defp intake_status(_event, proposed_changes, graph_links, run_links) do
    statuses = Enum.map(proposed_changes, & &1.status)
    linked_run_status = latest_linked_run_status(run_links)

    cond do
      not is_nil(linked_run_status) ->
        linked_run_status

      proposed_changes == [] ->
        "not_actionable"

      Enum.any?(statuses, &(&1 == "rejected")) ->
        "not_actionable"

      Enum.any?(statuses, &(&1 == "pending")) ->
        "pending_triage"

      Enum.all?(statuses, &(&1 == "applied")) and satisfied_verification_links?(graph_links) ->
        "verified"

      Enum.all?(statuses, &(&1 == "applied")) ->
        "ready_for_packet"

      true ->
        "not_actionable"
    end
  end

  defp latest_linked_run_status(run_links) do
    run_links
    |> Enum.find_value(fn
      %{type: "work_run", state: state} -> state
      _link -> nil
    end)
  end

  defp satisfied_verification_links?(graph_links) do
    verification_links = Enum.filter(graph_links, &(&1.type == "verification_check"))

    verification_links != [] and Enum.all?(verification_links, &(&1.state == "satisfied"))
  end

  defp intake_reason_codes(%{outcome: "duplicate"}, _proposed_changes), do: ["duplicate_intake"]

  defp intake_reason_codes(_event, proposed_changes) do
    statuses = Enum.map(proposed_changes, & &1.status)

    cond do
      proposed_changes == [] ->
        ["no_proposed_changes"]

      Enum.any?(statuses, &(&1 == "rejected")) ->
        ["rejected_proposed_change"]

      Enum.any?(statuses, &(&1 not in ["pending", "applied"])) ->
        ["unknown_proposed_change_state"]

      true ->
        []
    end
  end

  defp proposed_change_status(proposed_changes) do
    %{
      pending: Enum.count(proposed_changes, &(&1.status == "pending")),
      applied: Enum.count(proposed_changes, &(&1.status == "applied")),
      rejected: Enum.count(proposed_changes, &(&1.status == "rejected")),
      total: length(proposed_changes)
    }
  end

  defp blocker_reasons("not_actionable", reason_codes), do: reason_codes
  defp blocker_reasons(_status, _reason_codes), do: []

  defp allowed_next_actions("pending_triage"), do: ["apply_proposed_changes"]
  defp allowed_next_actions("ready_for_packet"), do: ["prepare_packet"]
  defp allowed_next_actions("not_actionable"), do: ["view_existing_intake"]
  defp allowed_next_actions(_status), do: []

  defp source_watermark([]), do: nil
  defp source_watermark([row | _rows]), do: row.operation_watermark

  defp read_scoped_many(_resource, _session_context, []), do: {:ok, []}

  defp read_scoped_many(resource, session_context, ids) do
    resource
    |> Ash.Query.filter(
      id in ^ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read(authorize?: false)
  end
end
