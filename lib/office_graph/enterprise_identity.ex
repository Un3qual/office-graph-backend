defmodule OfficeGraph.EnterpriseIdentity do
  @moduledoc """
  Provider-neutral enterprise connections, directories, and synchronized identity facts.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Identity,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.Tenancy
    ],
    exports: [Domain]
end
