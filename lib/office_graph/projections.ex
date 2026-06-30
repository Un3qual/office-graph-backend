defmodule OfficeGraph.Projections do
  @moduledoc """
  Public boundary for authorization-filtered graph projections.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Audit,
      OfficeGraph.Integrations,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Revisions,
      OfficeGraph.Runs,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph,
      OfficeGraph.WorkPackets
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.Audit.AuditRecord
  alias OfficeGraph.Integrations.NormalizedIntakeEvent
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Revisions.Revision
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkPackets

  alias OfficeGraph.WorkGraph.{
    EvidenceCandidate,
    GraphItem,
    GraphRelationship,
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck
  }

  alias OfficeGraph.WorkPackets.{WorkPacketRequiredCheck, WorkPacketSourceReference}

  require Ash.Query

  @allowed_autonomy_postures MapSet.new(["human_supervised"])
  @graph_resource_order %{
    "signal" => 0,
    "task" => 1,
    "review_finding" => 2,
    "verification_check" => 3
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
         {:ok, row} <- build_intake_row(session_context, event) do
      {:ok, row}
    end
  end

  def packet_readiness(session_context, attrs) when is_map(attrs) do
    with :ok <- authorize_read(session_context),
         {:ok, source_links, source_blockers} <- packet_source_links(session_context, attrs),
         {:ok, required_checks, check_blockers} <- packet_required_checks(session_context, attrs) do
      blockers =
        attrs
        |> readiness_blockers()
        |> Kernel.++(source_blockers)
        |> Kernel.++(check_blockers)
        |> Kernel.++(source_check_blockers(attrs, required_checks))
        |> Kernel.++(packet_create_action_blockers(session_context))
        |> Enum.uniq()

      ready? = blockers == []

      {:ok,
       %{
         type: "packet_readiness",
         ready?: ready?,
         status: if(ready?, do: "packet_ready", else: "blocked"),
         allowed_next_actions: if(ready?, do: ["create_work_packet"], else: []),
         blocker_reasons: blockers,
         source_links: source_links,
         required_checks: required_checks,
         source_watermark: nil
       }}
    end
  end

  def operator_run_state(session_context, run_id) do
    with {:ok, summary} <- Runs.get_summary(session_context, run_id),
         {:ok, evidence_candidates} <- read_evidence_candidates(session_context, summary.run.id) do
      {:ok, build_run_state(summary, evidence_candidates)}
    end
  end

  def verification_outcome(session_context, run_id) do
    with {:ok, run_state} <- operator_run_state(session_context, run_id) do
      {:ok,
       %{
         type: "verification_outcome",
         status: run_state.status,
         run: run_state.run,
         verification_results: run_state.verification_results,
         missing_evidence: run_state.missing_evidence,
         source_watermark: run_state.source_watermark
       }}
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

  defp build_intake_rows(session_context, events) do
    events
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, acc} ->
      case build_intake_row(session_context, event) do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp build_intake_row(session_context, event) do
    with {:ok, proposed_changes} <- read_proposed_changes(session_context, event),
         {:ok, applied_projection} <- applied_projection(session_context, proposed_changes),
         {:ok, run_links} <-
           run_links_for_graph_links(session_context, applied_projection.graph_links) do
      status = intake_status(event, proposed_changes, applied_projection.graph_links, run_links)
      reason_codes = intake_reason_codes(event, proposed_changes)
      graph_links = applied_projection.graph_links ++ run_links

      {:ok,
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
       }}
    end
  end

  defp read_proposed_changes(session_context, event) do
    ProposedGraphChange
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and normalized_event_id == ^event.id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp applied_projection(_session_context, []), do: {:ok, empty_applied_projection()}

  defp applied_projection(session_context, proposed_changes) do
    case applied_operation_id(proposed_changes) do
      nil ->
        {:ok, empty_applied_projection()}

      operation_id ->
        with {:ok, audit_records} <- read_audit_records(operation_id),
             {:ok, revision_records} <- read_revision_records(operation_id),
             {:ok, graph_links} <- graph_links_for_audit(session_context, audit_records),
             {:ok, graph_relationships} <- graph_relationships_for_links(graph_links) do
          {:ok,
           %{
             graph_links: graph_links,
             graph_relationships: graph_relationships,
             audit_trace: trace_summary(operation_id, audit_records),
             revision_trace: trace_summary(operation_id, revision_records)
           }}
        end
    end
  end

  defp empty_applied_projection do
    %{
      graph_links: [],
      graph_relationships: [],
      audit_trace: %{operation_id: nil, resource_count: 0, resources: []},
      revision_trace: %{operation_id: nil, resource_count: 0, resources: []}
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

  defp read_audit_records(operation_id) do
    AuditRecord
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_revision_records(operation_id) do
    Revision
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp graph_links_for_audit(session_context, audit_records) do
    audit_records
    |> Enum.filter(&Map.has_key?(@graph_resource_order, &1.resource_type))
    |> Enum.sort_by(&Map.fetch!(@graph_resource_order, &1.resource_type))
    |> Enum.reduce_while({:ok, []}, fn audit_record, {:ok, acc} ->
      case graph_link_for_resource(
             session_context,
             audit_record.resource_type,
             audit_record.resource_id
           ) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, link} -> {:cont, {:ok, [link | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, links} -> {:ok, Enum.reverse(links)}
      error -> error
    end
  end

  defp graph_link_for_resource(session_context, "signal", id) do
    with {:ok, signal} <- fetch_scoped(Signal, session_context, id) do
      {:ok, graph_link("signal", signal)}
    end
  end

  defp graph_link_for_resource(session_context, "task", id) do
    with {:ok, task} <- fetch_scoped(Task, session_context, id) do
      {:ok, graph_link("task", task)}
    end
  end

  defp graph_link_for_resource(session_context, "review_finding", id) do
    with {:ok, review_finding} <- fetch_scoped(ReviewFinding, session_context, id) do
      {:ok, graph_link("review_finding", review_finding)}
    end
  end

  defp graph_link_for_resource(session_context, "verification_check", id) do
    with {:ok, verification_check} <- fetch_scoped(VerificationCheck, session_context, id) do
      {:ok, graph_link("verification_check", verification_check)}
    end
  end

  defp graph_link_for_resource(_session_context, _resource_type, _id), do: {:ok, nil}

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

  defp run_links_for_graph_links(_session_context, []), do: {:ok, []}

  defp run_links_for_graph_links(session_context, graph_links) do
    verification_check_ids =
      graph_links
      |> Enum.filter(&(&1.type == "verification_check"))
      |> Enum.map(& &1.id)

    source_graph_item_ids =
      graph_links
      |> Enum.map(& &1.graph_item_id)
      |> Enum.reject(&is_nil/1)

    with {:ok, check_version_ids} <-
           work_packet_version_ids_for_checks(session_context, verification_check_ids),
         {:ok, source_version_ids} <-
           work_packet_version_ids_for_sources(session_context, source_graph_item_ids),
         version_ids = version_intersection(check_version_ids, source_version_ids),
         {:ok, runs} <- read_runs_for_versions(session_context, version_ids) do
      {:ok, Enum.map(runs, &run_graph_link/1)}
    end
  end

  defp work_packet_version_ids_for_checks(_session_context, []), do: {:ok, []}

  defp work_packet_version_ids_for_checks(session_context, verification_check_ids) do
    WorkPacketRequiredCheck
    |> Ash.Query.filter(
      verification_check_id in ^verification_check_ids and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, checks} -> {:ok, Enum.map(checks, & &1.work_packet_version_id)}
      {:error, error} -> {:error, error}
    end
  end

  defp work_packet_version_ids_for_sources(_session_context, []), do: {:ok, []}

  defp work_packet_version_ids_for_sources(session_context, source_graph_item_ids) do
    WorkPacketSourceReference
    |> Ash.Query.filter(
      graph_item_id in ^source_graph_item_ids and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, sources} -> {:ok, Enum.map(sources, & &1.work_packet_version_id)}
      {:error, error} -> {:error, error}
    end
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

  defp packet_source_links(session_context, attrs) do
    source_ids = Map.get(attrs, :source_graph_item_ids, [])

    with {:ok, graph_items} <- read_graph_items(session_context, source_ids) do
      found_ids = MapSet.new(graph_items, & &1.id)

      blockers =
        duplicate_source_id_blockers(source_ids) ++ missing_source_blockers(source_ids, found_ids)

      links =
        Enum.map(graph_items, fn graph_item ->
          %{
            type: graph_item.resource_type,
            id: graph_item.resource_id,
            graph_item_id: graph_item.id,
            title: graph_item.title
          }
        end)

      {:ok, links, blockers}
    end
  end

  defp duplicate_source_id_blockers(source_ids) do
    if length(source_ids) == length(Enum.uniq(source_ids)) do
      []
    else
      ["duplicate_source_graph_item_ids"]
    end
  end

  defp missing_source_blockers(source_ids, found_ids) do
    source_ids
    |> Enum.reject(&MapSet.member?(found_ids, &1))
    |> Enum.map(fn _id -> "missing_or_forbidden_source_graph_item" end)
    |> Enum.uniq()
  end

  defp packet_required_checks(session_context, attrs) do
    check_ids = Map.get(attrs, :verification_check_ids, [])

    with {:ok, checks} <- read_verification_checks(session_context, check_ids) do
      found_ids = MapSet.new(checks, & &1.id)

      blockers =
        duplicate_check_id_blockers(check_ids) ++
          missing_check_blockers(check_ids, found_ids) ++
          non_required_check_blockers(checks)

      required_checks =
        Enum.map(checks, fn check ->
          %{id: check.id, graph_item_id: check.graph_item_id, state: check.lifecycle_state}
        end)

      {:ok, required_checks, blockers}
    end
  end

  defp duplicate_check_id_blockers(check_ids) do
    if length(check_ids) == length(Enum.uniq(check_ids)) do
      []
    else
      ["duplicate_verification_check_ids"]
    end
  end

  defp missing_check_blockers(check_ids, found_ids) do
    check_ids
    |> Enum.reject(&MapSet.member?(found_ids, &1))
    |> Enum.map(fn _id -> "missing_or_forbidden_verification_check" end)
    |> Enum.uniq()
  end

  defp non_required_check_blockers(checks) do
    if Enum.any?(checks, &(&1.lifecycle_state != "required")) do
      ["non_required_verification_check"]
    else
      []
    end
  end

  defp source_check_blockers(attrs, required_checks) do
    source_graph_item_ids = Map.get(attrs, :source_graph_item_ids, [])

    if source_graph_item_ids != [] and required_checks != [] and
         WorkPackets.mismatched_source_check_ids(source_graph_item_ids, required_checks) != [] do
      ["source_graph_item_check_mismatch"]
    else
      []
    end
  end

  defp read_graph_items(_session_context, []), do: {:ok, []}

  defp read_graph_items(session_context, ids) do
    GraphItem
    |> Ash.Query.filter(
      id in ^ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_verification_checks(_session_context, []), do: {:ok, []}

  defp read_verification_checks(session_context, ids) do
    VerificationCheck
    |> Ash.Query.filter(
      id in ^ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp readiness_blockers(attrs) do
    [
      missing_string(attrs, :title, "missing_title"),
      missing_string(attrs, :objective, "missing_objective"),
      missing_string(attrs, :context_summary, "missing_context_summary"),
      missing_string(attrs, :requirements, "missing_requirements"),
      missing_string(attrs, :success_criteria, "missing_success_criteria"),
      missing_list(attrs, :source_graph_item_ids, "missing_source_graph_items"),
      missing_list(attrs, :verification_check_ids, "missing_verification_checks"),
      unsupported_autonomy_posture(attrs)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp packet_create_action_blockers(session_context) do
    case Authorization.authorize(session_context, :work_packet_create,
           organization_id: session_context.organization_id
         ) do
      :ok -> []
      {:error, :forbidden} -> ["missing_work_packet_create_capability"]
    end
  end

  defp missing_string(attrs, key, reason) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: reason

      _other ->
        reason
    end
  end

  defp missing_list(attrs, key, reason) do
    case Map.get(attrs, key) do
      list when is_list(list) ->
        if list == [], do: reason

      _other ->
        reason
    end
  end

  defp unsupported_autonomy_posture(attrs) do
    if MapSet.member?(@allowed_autonomy_postures, Map.get(attrs, :autonomy_posture)) do
      nil
    else
      "unsupported_autonomy_posture"
    end
  end

  defp read_evidence_candidates(session_context, run_id) do
    EvidenceCandidate
    |> Ash.Query.filter(
      work_run_id == ^run_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(authorize?: false)
  end

  defp build_run_state(summary, evidence_candidates) do
    status = run_status(summary, evidence_candidates)

    %{
      type: "operator_run_state",
      status: status,
      allowed_next_actions: run_next_actions(status),
      source_watermark: summary.run.id,
      packet: %{
        id: summary.packet.id,
        title: summary.packet.title,
        state: summary.packet.state
      },
      packet_version: %{
        id: summary.packet_version.id,
        version_number: summary.packet_version.version_number,
        lifecycle_state: summary.packet_version.lifecycle_state,
        objective: summary.packet_version.objective
      },
      run: %{
        id: summary.run.id,
        aggregate_state: summary.run.aggregate_state,
        execution_state: summary.run.execution_state,
        verification_state: summary.run.verification_state
      },
      required_checks:
        Enum.map(summary.required_checks, fn required_check ->
          %{
            id: required_check.id,
            verification_check_id: required_check.verification_check_id,
            state: required_check.state
          }
        end),
      observations:
        Enum.map(summary.observations, fn observation ->
          %{
            id: observation.id,
            verification_check_id: observation.verification_check_id,
            graph_item_id: observation.graph_item_id,
            normalized_status: observation.normalized_status,
            freshness_state: observation.freshness_state,
            trust_basis: observation.trust_basis,
            source_kind: observation.source_kind,
            source_identity: observation.source_identity
          }
        end),
      evidence_candidates: Enum.map(evidence_candidates, &evidence_candidate_projection/1),
      evidence_items:
        Enum.map(summary.evidence_items, fn evidence_item ->
          %{
            id: evidence_item.id,
            state: evidence_item.state,
            candidate_id: evidence_item.candidate_id,
            work_run_id: evidence_item.work_run_id
          }
        end),
      verification_results:
        Enum.map(summary.verification_results, fn result ->
          %{
            id: result.id,
            result: result.result,
            verification_check_id: result.verification_check_id,
            evidence_item_id: result.evidence_item_id,
            operation_id: result.operation_id,
            actor_principal_id: result.actor_principal_id,
            policy_basis: result.policy_basis,
            target_graph_item_id: result.target_graph_item_id,
            work_run_id: result.work_run_id,
            work_packet_version_id: result.work_packet_version_id
          }
        end),
      missing_evidence: Enum.map(summary.missing_evidence, &missing_evidence_projection/1)
    }
  end

  defp run_status(summary, _evidence_candidates)
       when summary.run.verification_state == "verified" or
              summary.run.aggregate_state == "verified" do
    "verified"
  end

  defp run_status(summary, _evidence_candidates)
       when summary.run.aggregate_state == "failed" or summary.run.verification_state == "failed" do
    "failed"
  end

  defp run_status(summary, evidence_candidates) do
    cond do
      pending_candidate_for_missing_check?(summary, evidence_candidates) ->
        "awaiting_evidence_acceptance"

      summary.observations != [] and summary.missing_evidence != [] ->
        "awaiting_evidence"

      summary.observations == [] ->
        "awaiting_execution"

      true ->
        "awaiting_evidence"
    end
  end

  defp run_next_actions("awaiting_execution"), do: ["record_observation"]
  defp run_next_actions("awaiting_evidence"), do: ["create_evidence_candidate"]
  defp run_next_actions("awaiting_evidence_acceptance"), do: ["accept_evidence"]
  defp run_next_actions(_status), do: []

  defp pending_candidate_for_missing_check?(summary, evidence_candidates) do
    missing_check_ids = MapSet.new(summary.missing_evidence, & &1.verification_check_id)

    Enum.any?(evidence_candidates, fn candidate ->
      candidate.candidate_state == "candidate" and
        MapSet.member?(missing_check_ids, candidate.verification_check_id) and
        Verification.acceptable_evidence_source?(candidate)
    end)
  end

  defp evidence_candidate_projection(candidate) do
    %{
      id: candidate.id,
      verification_check_id: candidate.verification_check_id,
      execution_observation_id: candidate.execution_observation_id,
      claim: candidate.claim,
      state: candidate.candidate_state,
      freshness_state: candidate.freshness_state,
      trust_basis: candidate.trust_basis,
      source_kind: candidate.source_kind,
      source_identity: candidate.source_identity
    }
  end

  defp missing_evidence_projection(%{
         verification_check_id: verification_check_id,
         reason: reason
       }) do
    %{verification_check_id: verification_check_id, reason: reason}
  end

  defp fetch_scoped(resource, session_context, id) do
    resource
    |> Ash.Query.filter(
      id == ^id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:ok, nil}
      {:ok, record} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end
end
