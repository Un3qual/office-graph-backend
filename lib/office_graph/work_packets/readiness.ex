defmodule OfficeGraph.WorkPackets.Readiness do
  @moduledoc false

  @allowed_autonomy_postures MapSet.new(["human_supervised"])

  def lifecycle_state(attrs) when is_map(attrs) do
    if ready?(attrs), do: "ready", else: "draft"
  end

  def ready?(attrs) when is_map(attrs) do
    present?(attrs[:objective]) and
      present?(attrs[:context_summary]) and
      present?(attrs[:requirements]) and
      present?(attrs[:success_criteria]) and
      MapSet.member?(@allowed_autonomy_postures, attrs[:autonomy_posture]) and
      references_present?(Map.get(attrs, :source_graph_item_ids, [])) and
      references_present?(Map.get(attrs, :verification_check_ids, []))
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

  defp references_present?(references) when is_list(references), do: references != []
  defp references_present?(_references), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
