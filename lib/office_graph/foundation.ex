defmodule OfficeGraph.Foundation do
  @moduledoc """
  Public boundary for cross-cutting foundation contracts.
  """

  use Boundary, deps: [OfficeGraph], exports: []
end
