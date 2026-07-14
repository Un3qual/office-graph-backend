defmodule OfficeGraph.SoftwareProving do
  @moduledoc """
  Public boundary for software proving artifacts and checks.
  """

  use Boundary,
    deps: [
      OfficeGraph.ExternalRefs,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.Tenancy
    ],
    exports: [
      CheckRun,
      Commit,
      Domain,
      PullRequest,
      Repository,
      RepositoryRef,
      ReviewComment,
      ReviewThread
    ]
end
