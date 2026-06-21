defmodule OfficeGraph.Integrations do
  @moduledoc """
  Public boundary for provider adapters and manual intake.
  """

  use Boundary, deps: [OfficeGraph], exports: []
end
