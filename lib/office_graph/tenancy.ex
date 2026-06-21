defmodule OfficeGraph.Tenancy do
  @moduledoc """
  Public boundary for organizations, workspaces, initiatives, and scopes.
  """

  use Boundary, deps: [OfficeGraph], exports: []
end
