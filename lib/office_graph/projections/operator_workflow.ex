defmodule OfficeGraph.Projections.OperatorWorkflow do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.Audit.AuditRecord
  alias OfficeGraph.Integrations.NormalizedIntakeEvent
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Projections.CommandAffordance
  alias OfficeGraph.Projections.KeysetCursor
  alias OfficeGraph.Repo
  alias OfficeGraph.Revisions.Revision
  alias OfficeGraph.WorkGraph.{GraphRelationship, ReviewFinding, Signal, Task, VerificationCheck}

  alias OfficeGraph.WorkPackets.{
    WorkPacketSourceReference,
    WorkPacketVersion
  }

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
  @default_operator_inbox_limit 50
  @max_operator_inbox_limit 100
  @relationship_summary_limit 20
  @summary_max_length 120
  @unsafe_summary_patterns [
    ~r/\b(?:api[ _-]?key|secret|token|password|passwd|credential|private[ _-]?key|authorization|cookie|session)[a-z0-9_-]*\s*[:=]\s*\S+/iu,
    ~r/\b(?:api[ _-]?key|secret|token|password|passwd|credential|private[ _-]?key)\s+(?:is|was)\s+\S+/iu,
    ~r/\b(?:bearer|basic)\s+\S+/iu,
    ~r/-----BEGIN [^-]+ PRIVATE KEY-----/iu,
    ~r/https?:\/\/\S+/iu,
    ~r/\b[\w.+-]+@[\w.-]+\.[a-z]{2,}\b/iu,
    ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/iu,
    ~r/\b[a-z0-9_+\/=\-]{32,}\b/iu
  ]

  def manual_intake_affordance(session_context) do
    affordance =
      if CommandAffordance.authorized?(session_context, :manual_intake_submit) do
        CommandAffordance.enabled(
          "submit_manual_intake",
          "Submit manual intake in the current workspace."
        )
      else
        CommandAffordance.policy_restricted("submit_manual_intake")
      end

    {:ok, affordance}
  end

  def operator_inbox(session_context, opts \\ []) do
    with {:ok, page} <- read_intake_rows_page(session_context, opts) do
      {:ok,
       %{
         type: "operator_inbox",
         rows: page.rows,
         empty?: page.rows == [],
         has_more?: page.has_more?,
         limit: page.limit,
         next_cursor: next_cursor(page.has_more?, page.events),
         after_cursor: page.after_cursor,
         source_watermark: source_watermark(page.rows)
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

  def relationship_details_page(session_context, normalized_event_id, opts) do
    limit = Keyword.fetch!(opts, :limit)
    after_cursor = Keyword.get(opts, :after_cursor)

    with :ok <- authorize_read(session_context),
         {:ok, normalized_event_id} <- normalize_event_id(normalized_event_id),
         {:ok, after_key} <- decode_relationship_cursor(after_cursor),
         {:ok, %{rows: rows}} <-
           Repo.query(
             relationship_details_sql(),
             relationship_detail_params(
               session_context,
               normalized_event_id,
               after_key,
               limit + 1
             )
           ) do
      detail_rows = Enum.reject(rows, &(List.first(&1) == nil))
      page_rows = Enum.take(detail_rows, limit)
      counts = relationship_counts_from_rows(rows)

      {:ok,
       %{
         edges:
           Enum.map(page_rows, fn row ->
             detail = relationship_detail_row(row)
             %{node: detail, cursor: KeysetCursor.encode([detail.kind, detail.stable_id])}
           end),
         has_next_page?: length(detail_rows) > limit,
         has_previous_page?: not is_nil(after_cursor),
         graph_link_count: counts.graph_links,
         graph_relationship_count: counts.graph_relationships
       }}
    end
  end

  defp relationship_details_sql do
    """
    WITH #{relationship_projection_ctes()}, detail_totals AS (
      SELECT event_id,
             count(*) FILTER (WHERE kind = 'graph_link') AS graph_link_count,
             count(*) FILTER (WHERE kind = 'graph_relationship') AS graph_relationship_count
      FROM details
      GROUP BY event_id
    ), paged_details AS (
      SELECT *
      FROM details
      WHERE event_id = $4
        AND ($5::text IS NULL OR (kind, stable_id) > ($5, $6))
      ORDER BY kind ASC, stable_id ASC
      LIMIT $7
    )
    SELECT paged_details.kind, paged_details.stable_id, paged_details.title,
           paged_details.status, paged_details.source_graph_item_id::text,
           paged_details.target_graph_item_id::text, paged_details.relationship_type,
           COALESCE(detail_totals.graph_link_count, 0),
           COALESCE(detail_totals.graph_relationship_count, 0)
    FROM requested_events
    LEFT JOIN detail_totals USING (event_id)
    LEFT JOIN paged_details USING (event_id)
    WHERE requested_events.event_id = $4
    ORDER BY paged_details.kind ASC NULLS LAST, paged_details.stable_id ASC NULLS LAST
    """
  end

  defp relationship_counts_sql do
    """
    WITH #{relationship_projection_ctes()}, counts AS (
      SELECT event_id,
             count(*) FILTER (WHERE kind = 'graph_link') AS graph_link_count,
             count(*) FILTER (WHERE kind = 'graph_relationship') AS graph_relationship_count
      FROM details
      GROUP BY event_id
    )
    SELECT requested_events.event_id::text,
           COALESCE(counts.graph_link_count, 0),
           COALESCE(counts.graph_relationship_count, 0)
    FROM requested_events
    LEFT JOIN counts USING (event_id)
    ORDER BY requested_events.event_id
    """
  end

  defp relationship_projection_ctes do
    """
    requested_events AS (
      SELECT unnest($1::uuid[]) AS event_id
    ), applied_links AS (
      SELECT pgc.normalized_event_id AS event_id, 'signal'::text AS link_type,
             s.id, s.graph_item_id, s.title, s.state AS status
      FROM proposed_graph_changes pgc JOIN signals s ON s.id = pgc.applied_resource_id
      WHERE pgc.normalized_event_id IN (SELECT event_id FROM requested_events)
        AND pgc.organization_id = $2 AND pgc.workspace_id = $3
        AND pgc.status = 'applied' AND pgc.change_type = 'create_signal'
        AND s.organization_id = $2 AND s.workspace_id = $3
      UNION ALL
      SELECT pgc.normalized_event_id, 'task', t.id, t.graph_item_id, t.title, t.lifecycle_state
      FROM proposed_graph_changes pgc JOIN tasks t ON t.id = pgc.applied_resource_id
      WHERE pgc.normalized_event_id IN (SELECT event_id FROM requested_events)
        AND pgc.organization_id = $2 AND pgc.workspace_id = $3
        AND pgc.status = 'applied' AND pgc.change_type = 'create_task'
        AND t.organization_id = $2 AND t.workspace_id = $3
      UNION ALL
      SELECT pgc.normalized_event_id, 'review_finding', rf.id, rf.graph_item_id, rf.title,
             rf.lifecycle_state
      FROM proposed_graph_changes pgc JOIN review_findings rf ON rf.id = pgc.applied_resource_id
      WHERE pgc.normalized_event_id IN (SELECT event_id FROM requested_events)
        AND pgc.organization_id = $2 AND pgc.workspace_id = $3
        AND pgc.status = 'applied' AND pgc.change_type = 'create_review_finding'
        AND rf.organization_id = $2 AND rf.workspace_id = $3
      UNION ALL
      SELECT pgc.normalized_event_id, 'verification_check', vc.id, vc.graph_item_id, vc.title,
             vc.lifecycle_state
      FROM proposed_graph_changes pgc JOIN verification_checks vc ON vc.id = pgc.applied_resource_id
      WHERE pgc.normalized_event_id IN (SELECT event_id FROM requested_events)
        AND pgc.organization_id = $2 AND pgc.workspace_id = $3
        AND pgc.status = 'applied' AND pgc.change_type = 'create_verification_check'
        AND vc.organization_id = $2 AND vc.workspace_id = $3
    ), source_matched_versions AS (
      SELECT DISTINCT applied_links.event_id, wps.work_packet_version_id
      FROM applied_links
      JOIN work_packet_version_sources wps
        ON wps.graph_item_id = applied_links.graph_item_id
       AND wps.organization_id = $2 AND wps.workspace_id = $3
    ), linked_versions AS (
      SELECT source_matched_versions.event_id, wpv.id, wpv.work_packet_id, wpv.version_number,
             wpv.title, wpv.lifecycle_state
      FROM source_matched_versions
      JOIN work_packet_versions wpv
        ON wpv.id = source_matched_versions.work_packet_version_id
       AND wpv.organization_id = $2 AND wpv.workspace_id = $3
      WHERE EXISTS (
          SELECT 1 FROM work_packet_version_required_checks wprc
          WHERE wprc.work_packet_version_id = wpv.id
            AND wprc.organization_id = $2 AND wprc.workspace_id = $3
            AND EXISTS (
              SELECT 1 FROM applied_links al
              WHERE al.event_id = source_matched_versions.event_id
                AND al.link_type = 'verification_check'
                AND al.id = wprc.verification_check_id
            )
        )
        AND NOT EXISTS (
          SELECT 1 FROM work_packet_version_required_checks wprc
          WHERE wprc.work_packet_version_id = wpv.id
            AND wprc.organization_id = $2 AND wprc.workspace_id = $3
            AND NOT EXISTS (
              SELECT 1 FROM applied_links al
              WHERE al.event_id = source_matched_versions.event_id
                AND al.link_type = 'verification_check'
                AND al.id = wprc.verification_check_id
            )
        )
        AND NOT EXISTS (
          SELECT 1 FROM applied_links al
          WHERE al.event_id = source_matched_versions.event_id
            AND al.link_type = 'verification_check'
            AND NOT EXISTS (
              SELECT 1 FROM work_packet_version_required_checks wprc
              WHERE wprc.work_packet_version_id = wpv.id
                AND wprc.organization_id = $2 AND wprc.workspace_id = $3
                AND wprc.verification_check_id = al.id
            )
        )
    ), packet_links AS (
      SELECT DISTINCT ON (event_id, work_packet_id) event_id, work_packet_id AS id,
             title, lifecycle_state AS status
      FROM linked_versions
      ORDER BY event_id, work_packet_id, version_number DESC
    ), workflow_links AS (
      SELECT event_id, 'work_packet'::text AS link_type, id, title, status
      FROM packet_links
      UNION ALL
      SELECT linked_versions.event_id, 'work_run', r.id, COALESCE(r.objective, 'Work run'),
             COALESCE(r.aggregate_state, r.state)
      FROM runs r
      JOIN linked_versions ON linked_versions.id = r.work_packet_version_id
      WHERE r.organization_id = $2 AND r.workspace_id = $3
    ), details AS (
      SELECT event_id, 'graph_link'::text AS kind, link_type || ':' || id::text AS stable_id,
             title, status, graph_item_id AS source_graph_item_id, NULL::uuid AS target_graph_item_id,
             link_type AS relationship_type
      FROM applied_links
      UNION ALL
      SELECT event_id, 'graph_link', link_type || ':' || id::text, title, status,
             NULL::uuid, NULL::uuid, link_type
      FROM workflow_links
      UNION ALL
      SELECT applied_sources.event_id, 'graph_relationship', gr.id::text,
             gr.relationship_type, NULL,
             gr.source_item_id, gr.target_item_id, gr.relationship_type
      FROM (
        SELECT DISTINCT event_id, graph_item_id FROM applied_links
      ) applied_sources
      JOIN graph_relationships gr ON gr.source_item_id = applied_sources.graph_item_id
      -- graph_relationships has no tenant columns, so both endpoint graph_items are the
      -- storage-boundary tenant constraint for this projection.
      JOIN graph_items source_gi ON source_gi.id = gr.source_item_id
        AND source_gi.organization_id = $2 AND source_gi.workspace_id = $3
      JOIN graph_items target_gi ON target_gi.id = gr.target_item_id
        AND target_gi.organization_id = $2 AND target_gi.workspace_id = $3
      WHERE EXISTS (
        SELECT 1 FROM applied_links target_link
        WHERE target_link.event_id = applied_sources.event_id
          AND target_link.graph_item_id = target_gi.id
      )
    )
    """
  end

  defp relationship_detail_params(session_context, event_id, after_key, limit) do
    {kind, stable_id} = after_key || {nil, nil}

    [
      [Ecto.UUID.dump!(event_id)],
      Ecto.UUID.dump!(session_context.organization_id),
      Ecto.UUID.dump!(session_context.workspace_id),
      Ecto.UUID.dump!(event_id),
      kind,
      stable_id,
      limit
    ]
  end

  defp relationship_detail_row([
         kind,
         stable_id,
         title,
         status,
         source_id,
         target_id,
         type,
         _graph_link_count,
         _graph_relationship_count
       ]) do
    %{
      kind: kind,
      stable_id: stable_id,
      title: title,
      status: status,
      source_graph_item_id: source_id,
      target_graph_item_id: target_id,
      relationship_type: type
    }
  end

  defp relationship_counts_from_rows([
         [_kind, _id, _title, _status, _source, _target, _type, links, relationships] | _rest
       ]),
       do: %{graph_links: links, graph_relationships: relationships}

  defp relationship_counts_from_rows([]), do: %{graph_links: 0, graph_relationships: 0}

  def operator_workflow_items_page(session_context, opts) do
    with {:ok, page} <- read_intake_rows_page(session_context, opts) do
      {:ok,
       %{
         rows: page.rows,
         row_edges: workflow_item_edges(page.rows, page.events),
         has_next_page?: page.has_more?,
         has_previous_page?: not is_nil(page.after_cursor)
       }}
    end
  end

  defp read_intake_rows_page(session_context, opts) do
    with {:ok, limit} <- page_limit(opts),
         :ok <- authorize_read(session_context),
         {:ok, cursor} <- page_cursor(opts),
         {:ok, events} <- read_intake_events(session_context, limit, cursor),
         page_events = Enum.take(events, limit),
         {:ok, rows} <- build_intake_rows(session_context, page_events) do
      {:ok,
       %{
         rows: rows,
         events: page_events,
         has_more?: length(events) > limit,
         limit: limit,
         after_cursor: option(opts, :after_cursor, nil)
       }}
    end
  end

  defp authorize_read(session_context) do
    Authorization.authorize_projection(session_context, :skeleton_read,
      organization_id: session_context.organization_id
    )
  end

  defp read_intake_events(session_context, limit, cursor) do
    NormalizedIntakeEvent
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> apply_inbox_cursor(cursor)
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(limit + 1)
    |> Ash.read(authorize?: false)
  end

  defp apply_inbox_cursor(query, nil), do: query

  defp apply_inbox_cursor(query, %{inserted_at: inserted_at, id: id}) do
    Ash.Query.filter(
      query,
      inserted_at < ^inserted_at or (inserted_at == ^inserted_at and id < ^id)
    )
  end

  defp page_limit(opts) do
    case option(opts, :limit, @default_operator_inbox_limit) do
      value when is_integer(value) and value < 0 -> {:error, {:invalid_field, :first}}
      value when is_integer(value) -> {:ok, Kernel.min(value, @max_operator_inbox_limit)}
      _other -> {:ok, @default_operator_inbox_limit}
    end
  end

  defp page_cursor(opts), do: decode_cursor(option(opts, :after_cursor, nil))

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [inserted_at_iso, id] <- String.split(decoded, "|", parts: 2),
         {:ok, inserted_at, _zone} <- DateTime.from_iso8601(inserted_at_iso),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, %{inserted_at: inserted_at, id: id}}
    else
      _error -> {:error, {:invalid_field, :after_cursor}}
    end
  end

  defp decode_cursor(_cursor), do: {:error, {:invalid_field, :after_cursor}}

  defp next_cursor(false, _events), do: nil

  defp next_cursor(true, events) do
    events
    |> List.last()
    |> encode_cursor()
  end

  defp encode_cursor(%{inserted_at: inserted_at, id: id}) do
    "#{DateTime.to_iso8601(inserted_at)}|#{id}"
    |> Base.url_encode64(padding: false)
  end

  defp option(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)
  defp option(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)

  defp workflow_item_edges(rows, events) do
    rows
    |> Enum.zip(events)
    |> Enum.map(fn {row, event} -> {row, cursor: encode_cursor(event)} end)
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
           applied_projections_by_event_id(session_context, events, proposed_changes_by_event_id),
         {:ok, relationship_counts_by_event_id} <-
           read_relationship_counts_by_event_id(session_context, event_ids) do
      command_authorizations = command_authorizations(session_context)

      rows =
        Enum.map(events, fn event ->
          proposed_changes = Map.get(proposed_changes_by_event_id, event.id, [])

          applied_projection =
            Map.get(applied_projections_by_event_id, event.id, empty_applied_projection())

          build_intake_row(
            session_context,
            command_authorizations,
            event,
            proposed_changes,
            applied_projection,
            Map.fetch!(relationship_counts_by_event_id, event.id)
          )
        end)

      {:ok, rows}
    end
  end

  defp command_authorizations(session_context) do
    %{
      proposed_change_apply:
        CommandAffordance.authorized?(session_context, :proposed_change_apply),
      work_packet_create: CommandAffordance.authorized?(session_context, :work_packet_create)
    }
  end

  defp build_intake_row(
         session_context,
         command_authorizations,
         event,
         proposed_changes,
         applied_projection,
         exact_relationship_counts
       ) do
    workflow_links = Map.get(applied_projection, :workflow_links, [])

    status =
      intake_status(event, proposed_changes, applied_projection.graph_links, workflow_links)

    reason_codes = intake_reason_codes(event, proposed_changes)
    graph_links = applied_projection.graph_links ++ workflow_links

    command_affordances =
      intake_command_affordances(
        session_context,
        command_authorizations,
        event,
        proposed_changes,
        status,
        reason_codes,
        graph_links,
        applied_projection.audit_trace
      )

    title = proposed_change_title(proposed_changes)
    graph_relationships = applied_projection.graph_relationships

    %{
      type: "operator_workflow_item",
      typed_id: %{type: "normalized_intake_event", id: event.id},
      normalized_event_id: event.id,
      duplicate_of_id: event.duplicate_of_id,
      title: title,
      source_summary: source_summary(title, proposed_changes),
      proposed_action_previews: proposed_action_previews(title, proposed_changes),
      status: status,
      reason_codes: reason_codes,
      source: %{
        identity: event.source_identity,
        replay_identity: event.replay_identity,
        outcome: event.outcome
      },
      proposed_change_status: proposed_change_status(proposed_changes),
      blocker_reasons: blocker_reasons(status, reason_codes),
      allowed_next_actions: CommandAffordance.enabled_identities(command_affordances),
      command_affordances: command_affordances,
      operation_watermark: event.operation_id,
      source_watermark: event.operation_id,
      graph_links: Enum.take(graph_links, @relationship_summary_limit),
      graph_relationships: Enum.take(graph_relationships, @relationship_summary_limit),
      relationship_summary: %{
        graph_links: exact_relationship_counts.graph_links,
        graph_relationships: exact_relationship_counts.graph_relationships,
        has_more:
          exact_relationship_counts.graph_links > @relationship_summary_limit or
            exact_relationship_counts.graph_relationships > @relationship_summary_limit
      },
      audit_trace: applied_projection.audit_trace,
      revision_trace: applied_projection.revision_trace
    }
  end

  defp proposed_change_title(proposed_changes) do
    Enum.find_value(proposed_changes, fn proposed_change ->
      safe_payload_summary(proposed_change.payload)
    end) || "Manual intake proposal"
  end

  defp read_relationship_counts_by_event_id(_session_context, []), do: {:ok, %{}}

  defp read_relationship_counts_by_event_id(session_context, event_ids) do
    params = [
      Enum.map(event_ids, &Ecto.UUID.dump!/1),
      Ecto.UUID.dump!(session_context.organization_id),
      Ecto.UUID.dump!(session_context.workspace_id)
    ]

    case Repo.query(relationship_counts_sql(), params) do
      {:ok, %{rows: rows}} ->
        {:ok,
         Map.new(rows, fn [event_id, graph_links, graph_relationships] ->
           {event_id, %{graph_links: graph_links, graph_relationships: graph_relationships}}
         end)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp source_summary(title, proposed_changes) do
    count = length(proposed_changes)

    "#{title} · #{count} proposed #{if(count == 1, do: "change", else: "changes")}"
  end

  defp proposed_action_previews(title, proposed_changes) do
    Enum.map(proposed_changes, fn proposed_change ->
      %{
        action: proposed_change.change_type,
        title: "#{proposed_action_label(proposed_change.change_type)}: #{title}",
        status: proposed_change.status
      }
    end)
  end

  defp safe_payload_summary(payload) when is_map(payload) do
    title = Map.get(payload, "title") || Map.get(payload, :title)
    body = Map.get(payload, "body") || Map.get(payload, :body)

    [title | summary_segments(body)]
    |> Enum.find_value(&safe_summary_candidate/1)
  end

  defp safe_payload_summary(_payload), do: nil

  defp summary_segments(body) when is_binary(body) do
    String.split(body, ~r/[.!?\n]+/u, trim: true)
  end

  defp summary_segments(_body), do: []

  defp safe_summary_candidate(candidate) when is_binary(candidate) do
    candidate = candidate |> String.replace(~r/\s+/u, " ") |> String.trim()

    if safe_summary_candidate?(candidate) do
      String.slice(candidate, 0, @summary_max_length)
    end
  end

  defp safe_summary_candidate(_candidate), do: nil

  defp safe_summary_candidate?(candidate) do
    candidate != "" and
      String.length(candidate) <= @summary_max_length and
      String.match?(candidate, ~r/^[\p{L}\p{N}\s.,:;!?'"()&+\/-]+$/u) and
      not Enum.any?(@unsafe_summary_patterns, &Regex.match?(&1, candidate))
  end

  defp proposed_action_label("create_signal"), do: "Proposed signal"
  defp proposed_action_label("create_task"), do: "Proposed task"
  defp proposed_action_label("create_review_finding"), do: "Proposed review finding"
  defp proposed_action_label("create_verification_check"), do: "Proposed verification check"
  defp proposed_action_label(_unknown), do: "Proposed change"

  defp decode_relationship_cursor(nil), do: {:ok, nil}

  defp decode_relationship_cursor(cursor) do
    with {:ok, [kind, stable_id]} <- KeysetCursor.decode(cursor, 2),
         true <- is_binary(kind) and is_binary(stable_id) do
      {:ok, {kind, stable_id}}
    else
      _invalid -> {:error, {:invalid_field, :pagination}}
    end
  end

  defp normalize_event_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_field, :id}}
    end
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
         {:ok, workflow_links_by_operation_id} <-
           workflow_links_by_operation_id(session_context, graph_links_by_operation_id) do
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
               workflow_links: Map.get(workflow_links_by_operation_id, operation_id, [])
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
      workflow_links: []
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

  defp workflow_links_by_operation_id(session_context, graph_links_by_operation_id) do
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
         verification_check_id_set = MapSet.new(verification_check_ids),
         matching_check_links =
           Enum.filter(
             check_links,
             &MapSet.member?(verification_check_id_set, &1.verification_check_id)
           ),
         version_ids_by_operation_id =
           version_ids_by_operation_id(
             graph_links_by_operation_id,
             matching_check_links,
             check_links,
             source_links
           ),
         version_ids = version_ids_by_operation_id |> flatten_map_values() |> Enum.uniq(),
         {:ok, packet_versions} <-
           read_scoped_many(WorkPacketVersion, session_context, version_ids),
         {:ok, runs_by_operation_id} <-
           read_runs_for_workflow_events(session_context, version_ids_by_operation_id) do
      packet_versions = Enum.sort_by(packet_versions, & &1.version_number, :desc)

      workflow_links_by_operation_id =
        Map.new(version_ids_by_operation_id, fn {operation_id, operation_version_ids} ->
          version_ids = MapSet.new(operation_version_ids)

          packet_links =
            packet_versions
            |> Enum.filter(&MapSet.member?(version_ids, &1.id))
            |> Enum.uniq_by(& &1.work_packet_id)
            |> Enum.map(&packet_graph_link/1)

          run_links =
            runs_by_operation_id
            |> Map.get(operation_id, [])
            |> Enum.map(&run_graph_link/1)

          {operation_id, packet_links ++ run_links}
        end)

      {:ok, workflow_links_by_operation_id}
    end
  end

  defp read_work_packet_required_checks(_session_context, []), do: {:ok, []}

  defp read_work_packet_required_checks(session_context, verification_check_ids) do
    sql = """
    WITH candidate_versions AS (
      SELECT DISTINCT work_packet_version_id
      FROM work_packet_version_required_checks
      WHERE verification_check_id = ANY($1::uuid[])
        AND organization_id = $2 AND workspace_id = $3
    )
    SELECT work_packet_version_id::text, verification_check_id::text
    FROM work_packet_version_required_checks
    WHERE work_packet_version_id IN (SELECT work_packet_version_id FROM candidate_versions)
      AND organization_id = $2 AND workspace_id = $3
    ORDER BY inserted_at, id
    """

    params = [
      Enum.map(verification_check_ids, &Ecto.UUID.dump!/1),
      Ecto.UUID.dump!(session_context.organization_id),
      Ecto.UUID.dump!(session_context.workspace_id)
    ]

    case Repo.query(sql, params) do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(rows, fn [work_packet_version_id, verification_check_id] ->
           %{
             work_packet_version_id: work_packet_version_id,
             verification_check_id: verification_check_id
           }
         end)}

      {:error, error} ->
        {:error, error}
    end
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

  defp version_ids_by_operation_id(
         graph_links_by_operation_id,
         matching_check_links,
         all_candidate_check_links,
         source_links
       ) do
    check_version_ids_by_check_id =
      Enum.group_by(
        matching_check_links,
        & &1.verification_check_id,
        & &1.work_packet_version_id
      )

    check_ids_by_version_id =
      Enum.group_by(
        all_candidate_check_links,
        & &1.work_packet_version_id,
        & &1.verification_check_id
      )

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

      expected_check_ids = MapSet.new(verification_check_ids)

      matching_version_ids =
        check_version_ids
        |> version_intersection(source_version_ids)
        |> Enum.filter(fn version_id ->
          version_check_ids = Map.get(check_ids_by_version_id, version_id, []) |> MapSet.new()
          MapSet.equal?(version_check_ids, expected_check_ids)
        end)

      {operation_id, matching_version_ids}
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

  defp read_runs_for_workflow_events(_session_context, version_ids_by_event)
       when map_size(version_ids_by_event) == 0,
       do: {:ok, %{}}

  defp read_runs_for_workflow_events(session_context, version_ids_by_event) do
    event_versions =
      for {event_key, version_ids} <- version_ids_by_event,
          version_id <- version_ids,
          do: {event_key, version_id}

    {event_keys, version_ids} = Enum.unzip(event_versions)

    sql = """
    WITH event_versions(event_key, version_id) AS (
      SELECT * FROM unnest($1::text[], $2::uuid[])
    ), ranked_runs AS (
      SELECT event_versions.event_key, r.id, r.work_packet_version_id, r.objective,
             r.state, r.aggregate_state,
             row_number() OVER (
               PARTITION BY event_key
               ORDER BY r.inserted_at DESC, r.id DESC
             ) AS event_rank
      FROM event_versions
      JOIN runs r ON r.work_packet_version_id = event_versions.version_id
      WHERE r.organization_id = $3 AND r.workspace_id = $4
    )
    SELECT event_key, id::text, work_packet_version_id::text, objective, state,
           aggregate_state
    FROM ranked_runs
    WHERE event_rank <= $5
    ORDER BY event_key, event_rank
    """

    params = [
      event_keys,
      Enum.map(version_ids, &Ecto.UUID.dump!/1),
      Ecto.UUID.dump!(session_context.organization_id),
      Ecto.UUID.dump!(session_context.workspace_id),
      @relationship_summary_limit + 1
    ]

    case Repo.query(sql, params) do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.group_by(
           rows,
           &List.first/1,
           fn [_event_key, id, work_packet_version_id, objective, state, aggregate_state] ->
             %{
               id: id,
               work_packet_version_id: work_packet_version_id,
               objective: objective,
               state: state,
               aggregate_state: aggregate_state
             }
           end
         )}

      {:error, error} ->
        {:error, error}
    end
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

  defp packet_graph_link(packet_version) do
    %{
      type: "work_packet",
      id: packet_version.work_packet_id,
      graph_item_id: nil,
      title: packet_version.title,
      state: packet_version.lifecycle_state
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

  defp intake_status(%{outcome: "duplicate"}, _proposed_changes, _graph_links, _workflow_links),
    do: "not_actionable"

  defp intake_status(_event, proposed_changes, graph_links, workflow_links) do
    status_summary = proposed_change_status_summary(proposed_changes)
    linked_run_status = latest_linked_run_status(workflow_links)

    cond do
      not is_nil(linked_run_status) ->
        linked_run_status

      proposed_changes == [] ->
        "not_actionable"

      status_summary.has_rejected ->
        "not_actionable"

      status_summary.has_pending ->
        "pending_triage"

      status_summary.all_applied and satisfied_verification_links?(graph_links) ->
        "verified"

      status_summary.all_applied and linked_packet?(workflow_links) ->
        "packet_created"

      status_summary.all_applied ->
        "ready_for_packet"

      true ->
        "not_actionable"
    end
  end

  defp linked_packet?(workflow_links) do
    Enum.any?(workflow_links, &(&1.type == "work_packet"))
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
    status_summary = proposed_change_status_summary(proposed_changes)

    cond do
      proposed_changes == [] ->
        ["no_proposed_changes"]

      status_summary.has_rejected ->
        ["rejected_proposed_change"]

      status_summary.has_unknown ->
        ["unknown_proposed_change_state"]

      true ->
        []
    end
  end

  defp proposed_change_status(proposed_changes) do
    summary = proposed_change_status_summary(proposed_changes)

    %{
      pending: summary.pending,
      applied: summary.applied,
      rejected: summary.rejected,
      total: summary.total
    }
  end

  defp proposed_change_status_summary(proposed_changes) do
    Enum.reduce(
      proposed_changes,
      %{
        pending: 0,
        applied: 0,
        rejected: 0,
        total: 0,
        has_pending: false,
        has_rejected: false,
        has_unknown: false,
        all_applied: true
      },
      fn proposed_change, acc ->
        acc = %{
          acc
          | total: acc.total + 1,
            all_applied: acc.all_applied and proposed_change.status == "applied"
        }

        case proposed_change.status do
          "pending" -> %{acc | pending: acc.pending + 1, has_pending: true}
          "applied" -> %{acc | applied: acc.applied + 1}
          "rejected" -> %{acc | rejected: acc.rejected + 1, has_rejected: true}
          _status -> %{acc | has_unknown: true}
        end
      end
    )
  end

  defp blocker_reasons("not_actionable", reason_codes), do: reason_codes
  defp blocker_reasons(_status, _reason_codes), do: []

  defp intake_command_affordances(
         _session_context,
         %{proposed_change_apply: false},
         _event,
         _proposed_changes,
         "pending_triage",
         _reason_codes,
         _graph_links,
         _trace
       ) do
    [CommandAffordance.policy_restricted("apply_proposed_changes")]
  end

  defp intake_command_affordances(
         _session_context,
         _command_authorizations,
         event,
         proposed_changes,
         "pending_triage",
         _reason_codes,
         _graph_links,
         _trace
       ) do
    [
      CommandAffordance.enabled(
        "apply_proposed_changes",
        "Apply pending proposed changes for this intake.",
        required_fields: ["normalized_event_id", "proposed_change_ids"],
        input_defaults: apply_input_defaults(event, proposed_changes),
        target_ids: [CommandAffordance.target_id("normalized_intake_event", event.id)]
      )
    ]
  end

  defp intake_command_affordances(
         _session_context,
         %{work_packet_create: false},
         event,
         _proposed_changes,
         "ready_for_packet",
         _reason_codes,
         graph_links,
         _trace
       ) do
    [
      CommandAffordance.policy_restricted("create_work_packet",
        required_fields: CommandAffordance.packet_required_fields(),
        input_defaults: packet_input_defaults(event, graph_links)
      )
    ]
  end

  defp intake_command_affordances(
         _session_context,
         _command_authorizations,
         event,
         _proposed_changes,
         "ready_for_packet",
         _reason_codes,
         graph_links,
         trace
       ) do
    [
      CommandAffordance.enabled(
        "create_work_packet",
        "Prepare a work packet from the applied intake.",
        required_fields: CommandAffordance.packet_required_fields(),
        input_defaults: packet_input_defaults(event, graph_links),
        target_ids: graph_link_target_ids(graph_links),
        trace_links: trace_links(trace)
      )
    ]
  end

  defp intake_command_affordances(
         _session_context,
         _command_authorizations,
         %{duplicate_of_id: duplicate_of_id},
         _proposed_changes,
         "not_actionable",
         reason_codes,
         _graph_links,
         _trace
       )
       when not is_nil(duplicate_of_id) do
    [
      CommandAffordance.enabled(
        "view_existing_intake",
        "Open the existing intake that already covers this source.",
        reason_codes: reason_codes,
        blocker_reasons: reason_codes,
        target_ids: [CommandAffordance.target_id("normalized_intake_event", duplicate_of_id)]
      )
    ]
  end

  defp intake_command_affordances(
         _session_context,
         _command_authorizations,
         _event,
         _proposed_changes,
         _status,
         _reason_codes,
         _graph_links,
         _trace
       ),
       do: []

  defp apply_input_defaults(event, proposed_changes) do
    [
      CommandAffordance.input_default("normalized_event_id", event.id),
      CommandAffordance.input_default("proposed_change_ids", Enum.map(proposed_changes, & &1.id))
    ]
  end

  defp graph_link_target_ids(graph_links) do
    graph_links
    |> Enum.map(&CommandAffordance.target_id(&1.type, &1.id))
    |> CommandAffordance.compact_target_ids()
  end

  defp packet_input_defaults(event, graph_links) do
    source_links =
      Enum.filter(graph_links, fn link -> link.graph_item_id && link.type != "work_run" end)

    verification_links = Enum.filter(graph_links, &(&1.type == "verification_check"))
    primary_verification_link = List.first(verification_links)
    source_titles = unique_non_blank(Enum.map(source_links, &(&1.title || "")))
    verification_titles = unique_non_blank(Enum.map(verification_links, &(&1.title || "")))
    title = first_non_blank(Enum.concat([verification_titles, source_titles, [event.id]]))
    source_summary = Enum.join(source_titles, "\n")
    verification_summary = Enum.join(verification_titles, "\n")

    [
      CommandAffordance.input_default("title", title),
      CommandAffordance.input_default("objective", title),
      CommandAffordance.input_default("context_summary", source_summary),
      CommandAffordance.input_default("requirements", source_summary),
      CommandAffordance.input_default("success_criteria", verification_summary),
      CommandAffordance.input_default("autonomy_posture", "human_supervised"),
      CommandAffordance.input_default(
        "source_graph_item_ids",
        Enum.map(source_links, & &1.graph_item_id)
      ),
      CommandAffordance.input_default(
        "verification_check_ids",
        Enum.map(verification_links, & &1.id)
      ),
      CommandAffordance.input_default(
        "primary_source_graph_item_id",
        primary_verification_link && primary_verification_link.graph_item_id
      ),
      CommandAffordance.input_default(
        "primary_verification_check_id",
        primary_verification_link && primary_verification_link.id
      )
    ]
  end

  defp unique_non_blank(values) do
    values
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp first_non_blank(values) do
    Enum.find_value(values, "", fn value ->
      trimmed = String.trim(value)
      if trimmed == "", do: nil, else: trimmed
    end)
  end

  defp trace_links(%{operation_id: nil}), do: []

  defp trace_links(%{operation_id: operation_id}) do
    [CommandAffordance.target_id("operation", operation_id)]
  end

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
