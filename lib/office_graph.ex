defmodule OfficeGraph do
  use Boundary,
    deps: [OfficeGraph.Repo],
    exports: [
      ApiSupport,
      Identity.SessionContext,
      Integrations,
      Operations,
      Projections,
      ProposedChanges,
      Runs,
      Verification,
      WorkGraph,
      WorkPackets
    ]

  @moduledoc """
  OfficeGraph keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
end
