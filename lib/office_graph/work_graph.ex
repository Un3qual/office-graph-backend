defmodule OfficeGraph.WorkGraph do
  @moduledoc """
  Public boundary for graph items, typed relationships, and graph reads.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Audit,
      OfficeGraph.Content,
      OfficeGraph.Identity,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Revisions,
      OfficeGraph.Tenancy,
      OfficeGraph.Tombstones
    ],
    exports: []

  alias OfficeGraph.WorkGraph.{
    ProposalCommands,
    Queries,
    RelationshipDefinitions,
    VerificationCommands
  }

  defdelegate graphql_node_type(value), to: Queries
  defdelegate graphql_node(session_context, type, id), to: Queries

  defdelegate get_verification_check(session_context, id),
    to: Queries

  defdelegate fetch_relationship_definition(key),
    to: RelationshipDefinitions,
    as: :fetch_by_key

  defdelegate create_signal(session_context, operation, attrs),
    to: ProposalCommands

  defdelegate create_task(session_context, operation, signal, attrs),
    to: ProposalCommands

  defdelegate create_review_finding(session_context, operation, task, attrs),
    to: ProposalCommands

  defdelegate create_verification_check(session_context, operation, review_finding, attrs),
    to: ProposalCommands

  defdelegate complete_verification(session_context, operation, verification_check, attrs),
    to: VerificationCommands

  defdelegate satisfy_verification_check_from_evidence(
                session_context,
                operation,
                verification_check
              ),
              to: VerificationCommands
end
