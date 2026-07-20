defmodule OfficeGraph.GitHubIntegration.ReviewReplyMarker do
  @moduledoc false

  @marker_pattern ~r/(?:\A|\r?\n\r?\n)<!-- office-graph-action:([^\s<>]+) -->\s*\z/

  def render(action_id) when is_binary(action_id),
    do: "<!-- office-graph-action:#{action_id} -->"

  def own_reply?(body) when is_binary(body), do: Regex.match?(@marker_pattern, body)
  def own_reply?(_body), do: false

  def action_id(body) when is_binary(body) do
    case Regex.run(@marker_pattern, body, capture: :all_but_first) do
      [action_id] -> normalize_action_id(action_id)
      _no_marker -> nil
    end
  end

  def action_id(_body), do: nil

  defp normalize_action_id(action_id) do
    case Ecto.UUID.cast(action_id) do
      {:ok, normalized} -> normalized
      :error -> nil
    end
  end
end
