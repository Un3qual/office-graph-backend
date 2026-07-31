defmodule OfficeGraph.Identity.SessionContext do
  @moduledoc """
  Authenticated principal/session context passed to API entrypoints and domain actions.
  """

  defstruct [
    :principal_id,
    :session_id,
    :organization_id,
    :workspace_id,
    :external_identity_link_id,
    :enterprise_connection_id,
    :authentication_method,
    capabilities: MapSet.new(),
    trusted?: false
  ]
end
