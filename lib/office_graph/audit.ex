defmodule OfficeGraph.Audit do
  @moduledoc """
  Public boundary for audit record creation and retrieval.
  """

  use Boundary, deps: [OfficeGraph], exports: []
end
