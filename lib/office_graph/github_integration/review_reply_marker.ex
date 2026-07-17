defmodule OfficeGraph.GitHubIntegration.ReviewReplyMarker do
  @moduledoc false

  @marker_pattern ~r/(?:\A|\r?\n\r?\n)<!-- office-graph-action:[^\s<>]+ -->\s*\z/

  def render(action_id) when is_binary(action_id),
    do: "<!-- office-graph-action:#{action_id} -->"

  def own_reply?(body) when is_binary(body), do: Regex.match?(@marker_pattern, body)
  def own_reply?(_body), do: false
end
