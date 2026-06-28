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

  defp references_present?(references) when is_list(references), do: references != []
  defp references_present?(_references), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
