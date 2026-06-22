defmodule OfficeGraph.Tombstones do
  @moduledoc """
  Public boundary for soft-delete tombstone records.
  """

  use Boundary, deps: [OfficeGraph], exports: []
end
