defmodule OfficeGraph.AgentRuntime do
  @moduledoc """
  Public boundary for governed, run-linked agent runtime orchestration.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.ExternalRefs,
      OfficeGraph.Identity,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Runs,
      OfficeGraph.Tenancy,
      OfficeGraph.WorkGraph
    ],
    exports: []
end
