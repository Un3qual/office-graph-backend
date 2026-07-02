defmodule OfficeGraph.Projections do
  @moduledoc """
  Public boundary for authorization-filtered graph projections.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Audit,
      OfficeGraph.Integrations,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Revisions,
      OfficeGraph.Runs,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph,
      OfficeGraph.WorkPackets
    ],
    exports: []

  alias OfficeGraph.Projections.{OperatorWorkflow, PacketReadiness, RunState}

  defdelegate operator_inbox(session_context), to: OperatorWorkflow
  defdelegate operator_workflow_item(session_context, normalized_event_id), to: OperatorWorkflow
  defdelegate packet_readiness(session_context, attrs), to: PacketReadiness
  defdelegate operator_run_state(session_context, run_id), to: RunState
  defdelegate verification_outcome(session_context, run_id), to: RunState
end
