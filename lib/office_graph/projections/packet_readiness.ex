defmodule OfficeGraph.Projections.PacketReadiness do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.Projections.CommandAffordance
  alias OfficeGraph.WorkGraph.{GraphItem, VerificationCheck}
  alias OfficeGraph.WorkPackets

  require Ash.Query

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

      command_affordances =
        packet_command_affordances(ready?, blockers, source_links, required_checks)

      {:ok,
       %{
         type: "packet_readiness",
         ready?: ready?,
         status: if(ready?, do: "packet_ready", else: "blocked"),
         allowed_next_actions: CommandAffordance.enabled_identities(command_affordances),
         command_affordances: command_affordances,
         blocker_reasons: blockers,
         source_links: source_links,
         required_checks: required_checks,
         source_watermark: nil
       }}
    end
  end

  defp authorize_read(session_context) do
    Authorization.authorize(session_context, :skeleton_read,
      organization_id: session_context.organization_id
    )
  end

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
      WorkPackets.missing_string_blocker(attrs, :title, "missing_title")
      | WorkPackets.readiness_blocker_reasons(attrs)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp packet_create_action_blockers(session_context) do
    case Authorization.authorize(session_context, :work_packet_create,
           organization_id: session_context.organization_id
         ) do
      :ok -> []
      {:error, :forbidden} -> ["policy_restricted"]
    end
  end

  defp packet_command_affordances(ready?, blockers, source_links, required_checks) do
    cond do
      "policy_restricted" in blockers ->
        [
          CommandAffordance.hidden(
            "create_work_packet",
            "This command is not available for the current operator.",
            reason_codes: ["policy_restricted"],
            blocker_reasons: ["policy_restricted"],
            required_fields: CommandAffordance.packet_required_fields()
          )
        ]

      ready? ->
        [
          CommandAffordance.enabled(
            "create_work_packet",
            "Create a work packet from the selected sources and checks.",
            required_fields: CommandAffordance.packet_required_fields(),
            target_ids: packet_target_ids(source_links, required_checks)
          )
        ]

      true ->
        [
          CommandAffordance.disabled(
            "create_work_packet",
            "Resolve packet readiness blockers before creating a work packet.",
            reason_codes: blockers,
            blocker_reasons: blockers,
            required_fields: CommandAffordance.packet_required_fields(),
            target_ids: packet_target_ids(source_links, required_checks)
          )
        ]
    end
  end

  defp packet_target_ids(source_links, required_checks) do
    source_targets =
      Enum.map(source_links, &CommandAffordance.target_id("graph_item", &1.graph_item_id))

    check_targets =
      Enum.map(required_checks, &CommandAffordance.target_id("verification_check", &1.id))

    CommandAffordance.compact_target_ids(source_targets ++ check_targets)
  end
end
