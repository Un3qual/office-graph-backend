defmodule OfficeGraph.Identity.SessionContext do
  @moduledoc """
  Authenticated principal/session context passed to API entrypoints and domain actions.
  """

  defstruct [
    :principal_id,
    :session_id,
    :organization_id,
    :workspace_id,
    capabilities: MapSet.new()
  ]
end
