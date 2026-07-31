defmodule OfficeGraph.WorkPackets.Readiness do
  @moduledoc false

  @allowed_autonomy_postures MapSet.new(["human_supervised"])

  def lifecycle_state(attrs) when is_map(attrs) do
    if ready?(attrs), do: "ready", else: "draft"
  end

  def ready?(attrs) when is_map(attrs) do
    blocker_reasons(attrs) == []
  end

  def blocker_reasons(attrs) when is_map(attrs) do
    [
      missing_string_blocker(attrs, :objective, "missing_objective"),
      missing_string_blocker(attrs, :context_summary, "missing_context_summary"),
      missing_string_blocker(attrs, :requirements, "missing_requirements"),
      missing_string_blocker(attrs, :success_criteria, "missing_success_criteria"),
      missing_list(attrs, :source_graph_item_ids, "missing_source_graph_items"),
      missing_list(attrs, :verification_check_ids, "missing_verification_checks"),
      unsupported_autonomy_posture(attrs)
    ]
    |> Enum.reject(&is_nil/1)
  end

  def mismatched_source_check_ids(source_graph_item_ids, verification_checks)
      when is_list(source_graph_item_ids) and is_list(verification_checks) do
    source_graph_item_ids = MapSet.new(source_graph_item_ids)

    verification_checks
    |> Enum.reject(fn check ->
      MapSet.member?(source_graph_item_ids, check.graph_item_id)
    end)
    |> Enum.map(& &1.id)
  end

  def missing_string_blocker(attrs, key, reason) when is_map(attrs) do
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
end
