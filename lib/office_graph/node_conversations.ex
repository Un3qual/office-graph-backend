defmodule OfficeGraph.NodeConversations do
  @moduledoc """
  Public boundary for run-aware graph conversations and message provenance.
  """

  use Boundary,
    deps: [
      OfficeGraph.Identity,
      OfficeGraph.Operations,
      OfficeGraph.Runs,
      OfficeGraph.WorkGraph
    ],
    exports: []
end
