defmodule OfficeGraph.Projections.PacketWorkspace do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.Projections.CommandAffordance
  alias OfficeGraph.Projections.KeysetCursor
  alias OfficeGraph.Runs
  alias OfficeGraph.Runs.Run

  alias OfficeGraph.WorkGraph.VerificationCheck

  alias OfficeGraph.WorkPackets.{
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

  alias OfficeGraph.WorkPackets

  require Ash.Query

  @run_required_fields [
    "packet_version_id",
    "source_surface",
    "reason",
    "authority_posture"
  ]

  def packet_create_affordance(session_context) do
    affordance =
      if CommandAffordance.authorized?(session_context, :work_packet_create) do
        CommandAffordance.enabled(
          "create_work_packet",
          "Create a work packet in the current workspace.",
          required_fields: CommandAffordance.packet_required_fields()
        )
      else
        CommandAffordance.policy_restricted("create_work_packet",
          required_fields: CommandAffordance.packet_required_fields()
        )
      end

    {:ok, affordance}
  end

  def packet_workspace(session_context, packet_id) do
    with :ok <- authorize_read(session_context),
         {:ok, packet} <- read_packet(session_context, packet_id),
         {:ok, current_version} <- read_current_version(session_context, packet),
         {:ok, source_references} <- read_source_references(session_context, [current_version]),
         {:ok, required_checks} <- read_required_checks(session_context, [current_version]),
         {:ok, version_count} <- count_versions(session_context, packet.id),
         {:ok, verification_checks} <-
           read_verification_checks(session_context, current_version, required_checks),
         {:ok, current_version_runs} <-
           read_current_version_runs(session_context, current_version.id) do
      {:ok,
       build_workspace(
         session_context,
         packet,
         current_version,
         version_count,
         source_references,
         required_checks,
         verification_checks,
         current_version_runs
       )}
    end
  end

  def version_history_page(session_context, packet_id, opts) do
    limit = Keyword.fetch!(opts, :limit)
    after_cursor = Keyword.get(opts, :after_cursor)

    with :ok <- authorize_read(session_context),
         {:ok, _packet} <- read_packet(session_context, packet_id),
         {:ok, after_key} <- decode_version_cursor(after_cursor),
         {:ok, versions} <- read_versions_page(session_context, packet_id, after_key, limit + 1) do
      page_versions = Enum.take(versions, limit)
      has_next_page? = length(versions) > limit

      {:ok,
       %{
         edges:
           Enum.map(page_versions, fn version ->
             %{
               node: version_history_projection(version),
               cursor: version_cursor(version)
             }
           end),
         has_next_page?: has_next_page?,
         has_previous_page?: not is_nil(after_cursor)
       }}
    end
  end

  defp authorize_read(session_context) do
    Authorization.authorize_projection(session_context, :skeleton_read,
      organization_id: session_context.organization_id
    )
  end

  defp read_packet(session_context, packet_id) do
    WorkPacket
    |> Ash.Query.filter(
      id == ^packet_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, WorkPacket, packet_id}}
      result -> result
    end
  end

  defp read_versions_page(session_context, packet_id, after_key, limit) do
    WorkPacketVersion
    |> Ash.Query.filter(
      work_packet_id == ^packet_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(version_number: :asc, inserted_at: :asc, id: :asc)
    |> after_version(after_key)
    |> Ash.Query.limit(limit)
    |> Ash.read(authorize?: false)
  end

  defp after_version(query, nil), do: query

  defp after_version(query, {version_number, id}) do
    Ash.Query.filter(
      query,
      version_number > ^version_number or (version_number == ^version_number and id > ^id)
    )
  end

  defp count_versions(session_context, packet_id) do
    WorkPacketVersion
    |> Ash.Query.filter(
      work_packet_id == ^packet_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.count(authorize?: false)
  end

  defp read_current_version(_session_context, %{current_version_id: nil} = packet),
    do: {:error, {:not_found, WorkPacketVersion, packet.id}}

  defp read_current_version(session_context, packet) do
    WorkPacketVersion
    |> Ash.Query.filter(
      id == ^packet.current_version_id and work_packet_id == ^packet.id and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, WorkPacketVersion, packet.current_version_id}}
      result -> result
    end
  end

  defp read_source_references(session_context, versions) do
    version_ids = Enum.map(versions, & &1.id)

    WorkPacketSourceReference
    |> Ash.Query.filter(
      work_packet_version_id in ^version_ids and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(position: :asc, inserted_at: :asc, id: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_required_checks(session_context, versions) do
    version_ids = Enum.map(versions, & &1.id)

    WorkPacketRequiredCheck
    |> Ash.Query.filter(
      work_packet_version_id in ^version_ids and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.sort(position: :asc, inserted_at: :asc, id: :asc)
    |> Ash.read(authorize?: false)
  end

  defp read_verification_checks(session_context, current_version, required_checks) do
    check_ids =
      required_checks
      |> Enum.filter(&(&1.work_packet_version_id == current_version.id))
      |> Enum.map(& &1.verification_check_id)

    VerificationCheck
    |> Ash.Query.filter(
      id in ^check_ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and lifecycle_state == "required"
    )
    |> Ash.read(authorize?: false)
  end

  defp read_current_version_runs(session_context, current_version_id) do
    Run
    |> Ash.Query.filter(
      work_packet_version_id == ^current_version_id and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and state not in ["failed", "verified"] and
        aggregate_state not in ["failed", "verified"] and
        verification_state not in ["failed", "verified"]
    )
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read(actor: session_context)
  end

  defp build_workspace(
         session_context,
         packet,
         current_version,
         version_count,
         source_references,
         required_checks,
         verification_checks,
         current_version_runs
       ) do
    source_ids = ids_for_version(source_references, current_version.id, :graph_item_id)

    check_ids =
      ids_for_version(required_checks, current_version.id, :verification_check_id)

    blockers =
      current_version
      |> version_attrs(source_ids, check_ids)
      |> WorkPackets.readiness_blocker_reasons()
      |> Kernel.++(verification_check_blockers(check_ids, verification_checks))
      |> Kernel.++(source_check_mismatch_blockers(source_ids, verification_checks))
      |> Kernel.++(run_start_policy_blockers(session_context))
      |> Enum.uniq()

    ready? = blockers == []

    command_affordances =
      version_create_affordance(session_context, packet, current_version, source_ids, check_ids) ++
        run_start_affordances(
          session_context,
          packet,
          current_version,
          blockers,
          Enum.find(current_version_runs, &Runs.active_run?/1)
        )

    workspace = %{
      type: "operator_packet_workspace",
      packet: packet_projection(packet),
      current_version: version_projection(current_version, source_references, required_checks),
      version_count: version_count,
      ready?: ready?,
      status: if(ready?, do: "ready_for_run", else: "blocked"),
      blocker_reasons: blockers,
      allowed_next_actions: CommandAffordance.enabled_identities(command_affordances),
      command_affordances: command_affordances
    }

    Map.put(workspace, :source_watermark, projection_watermark(workspace))
  end

  defp packet_projection(packet) do
    %{
      id: packet.id,
      title: packet.title,
      state: packet.state,
      current_version_id: packet.current_version_id,
      operation_id: packet.operation_id
    }
  end

  defp version_projection(version, source_references, required_checks) do
    %{
      id: version.id,
      version_number: version.version_number,
      lifecycle_state: version.lifecycle_state,
      title: version.title,
      objective: version.objective,
      context_summary: version.context_summary,
      requirements: version.requirements,
      success_criteria: version.success_criteria,
      autonomy_posture: version.autonomy_posture,
      source_graph_item_ids: ids_for_version(source_references, version.id, :graph_item_id),
      verification_check_ids:
        ids_for_version(required_checks, version.id, :verification_check_id),
      operation_id: version.operation_id,
      inserted_at: version.inserted_at
    }
  end

  defp version_history_projection(version) do
    %{
      id: version.id,
      version_number: version.version_number,
      lifecycle_state: version.lifecycle_state,
      title: version.title,
      objective: version.objective,
      context_summary: version.context_summary,
      requirements: version.requirements,
      success_criteria: version.success_criteria,
      autonomy_posture: version.autonomy_posture,
      source_graph_item_ids: [],
      verification_check_ids: [],
      operation_id: version.operation_id,
      inserted_at: version.inserted_at
    }
  end

  defp version_cursor(version),
    do: KeysetCursor.encode([version.version_number, version.id])

  defp decode_version_cursor(nil), do: {:ok, nil}

  defp decode_version_cursor(cursor) do
    with {:ok, [version_number, id]} <- KeysetCursor.decode(cursor, 2),
         true <- is_integer(version_number) and is_binary(id) do
      {:ok, {version_number, id}}
    else
      _invalid -> {:error, {:invalid_field, :pagination}}
    end
  end

  defp version_attrs(version, source_ids, check_ids) do
    %{
      objective: version.objective,
      context_summary: version.context_summary,
      requirements: version.requirements,
      success_criteria: version.success_criteria,
      autonomy_posture: version.autonomy_posture,
      source_graph_item_ids: source_ids,
      verification_check_ids: check_ids
    }
  end

  defp ids_for_version(records, version_id, field) do
    records
    |> Enum.filter(&(&1.work_packet_version_id == version_id))
    |> Enum.map(&Map.fetch!(&1, field))
  end

  defp verification_check_blockers(check_ids, verification_checks) do
    if length(check_ids) == length(verification_checks) do
      []
    else
      ["missing_or_non_required_verification_check"]
    end
  end

  defp source_check_mismatch_blockers(source_ids, verification_checks) do
    case WorkPackets.mismatched_source_check_ids(source_ids, verification_checks) do
      [] -> []
      _mismatched_check_ids -> ["source_graph_item_check_mismatch"]
    end
  end

  defp version_create_affordance(
         session_context,
         packet,
         current_version,
         source_ids,
         check_ids
       ) do
    required_fields = [
      "packet_id",
      "expected_current_version_id" | CommandAffordance.packet_required_fields()
    ]

    if CommandAffordance.authorized?(session_context, :work_packet_version_create) do
      [
        CommandAffordance.enabled(
          "create_work_packet_version",
          "Create the next immutable version of this work packet.",
          required_fields: required_fields,
          input_defaults:
            version_create_input_defaults(packet, current_version, source_ids, check_ids),
          target_ids: [
            CommandAffordance.target_id("work_packet", packet.id),
            CommandAffordance.target_id("work_packet_version", current_version.id)
          ]
        )
      ]
    else
      [
        CommandAffordance.policy_restricted("create_work_packet_version",
          required_fields: required_fields
        )
      ]
    end
  end

  defp version_create_input_defaults(packet, current_version, source_ids, check_ids) do
    [
      CommandAffordance.input_default("packet_id", packet.id),
      CommandAffordance.input_default("expected_current_version_id", current_version.id),
      CommandAffordance.input_default("title", current_version.title),
      CommandAffordance.input_default("objective", current_version.objective),
      CommandAffordance.input_default("context_summary", current_version.context_summary),
      CommandAffordance.input_default("requirements", current_version.requirements),
      CommandAffordance.input_default("success_criteria", current_version.success_criteria),
      CommandAffordance.input_default("autonomy_posture", current_version.autonomy_posture),
      CommandAffordance.input_default("source_graph_item_ids", source_ids),
      CommandAffordance.input_default("verification_check_ids", check_ids)
    ]
  end

  defp run_start_policy_blockers(session_context) do
    if CommandAffordance.authorized?(session_context, :work_run_start) do
      []
    else
      ["policy_restricted"]
    end
  end

  defp run_start_affordances(
         session_context,
         packet,
         current_version,
         blockers,
         active_run
       ) do
    cond do
      not CommandAffordance.authorized?(session_context, :work_run_start) ->
        [
          CommandAffordance.policy_restricted("start_work_run",
            required_fields: @run_required_fields
          )
        ]

      blockers == [] and not is_nil(active_run) ->
        [
          CommandAffordance.disabled(
            "start_work_run",
            "Wait for the current packet version's active run to finish.",
            reason_codes: ["active_work_run"],
            blocker_reasons: ["active_work_run"],
            required_fields: @run_required_fields,
            input_defaults: run_start_input_defaults(current_version),
            target_ids: [
              CommandAffordance.target_id("work_packet", packet.id),
              CommandAffordance.target_id("work_packet_version", current_version.id),
              CommandAffordance.target_id("work_run", active_run.id)
            ]
          )
        ]

      blockers == [] ->
        [
          CommandAffordance.enabled(
            "start_work_run",
            "Start a work run from the current packet version.",
            required_fields: @run_required_fields,
            input_defaults: run_start_input_defaults(current_version),
            target_ids: [
              CommandAffordance.target_id("work_packet", packet.id),
              CommandAffordance.target_id("work_packet_version", current_version.id)
            ]
          )
        ]

      true ->
        [
          CommandAffordance.disabled(
            "start_work_run",
            "Resolve packet readiness blockers before starting a work run.",
            reason_codes: blockers,
            blocker_reasons: blockers,
            required_fields: @run_required_fields,
            input_defaults: run_start_input_defaults(current_version),
            target_ids: [
              CommandAffordance.target_id("work_packet", packet.id),
              CommandAffordance.target_id("work_packet_version", current_version.id)
            ]
          )
        ]
    end
  end

  defp run_start_input_defaults(current_version) do
    [
      CommandAffordance.input_default("packet_version_id", current_version.id),
      CommandAffordance.input_default("source_surface", "packet_workspace"),
      CommandAffordance.input_default("reason", "Start work from the packet workspace."),
      CommandAffordance.input_default("authority_posture", current_version.autonomy_posture)
    ]
  end

  defp projection_watermark(data) do
    data
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
