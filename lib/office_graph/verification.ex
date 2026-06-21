defmodule OfficeGraph.Verification do
  @moduledoc """
  Public boundary for verification checks, evidence, and results.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.WorkGraph

  def complete_with_evidence(session_context, operation, verification_check, attrs) do
    with :ok <-
           Authorization.authorize(session_context, :evidence_link,
             organization_id: session_context.organization_id
           ),
         :ok <-
           Authorization.authorize(session_context, :verification_complete,
             organization_id: session_context.organization_id
           ) do
      WorkGraph.complete_verification(session_context, operation, verification_check, attrs)
    end
  end
end
