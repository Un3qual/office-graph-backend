defmodule OfficeGraph.CommandSupport do
  @moduledoc """
  Shared typed identities and safe errors for public Ash command actions.
  """

  use Boundary, exports: [CommandError, TypedId]
end
