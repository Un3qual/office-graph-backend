defmodule OfficeGraph.Authorization do
  @moduledoc """
  Public boundary for authorization decisions and capability checks.
  """

  use Boundary, deps: [OfficeGraph], exports: []
end
