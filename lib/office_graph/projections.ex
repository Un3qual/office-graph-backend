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

  alias OfficeGraph.Projections.{OperatorWorkflow, PacketReadiness, PacketWorkspace, RunState}
  alias OfficeGraph.{Runs, WorkGraph, WorkPackets}

  defdelegate operator_inbox(session_context), to: OperatorWorkflow
  defdelegate operator_inbox(session_context, opts), to: OperatorWorkflow
  defdelegate operator_workflow_items_page(session_context, opts), to: OperatorWorkflow
  defdelegate operator_workflow_item(session_context, normalized_event_id), to: OperatorWorkflow
  defdelegate packet_readiness(session_context, attrs), to: PacketReadiness
  defdelegate packet_workspace(session_context, packet_id), to: PacketWorkspace
  defdelegate packet_create_affordance(session_context), to: PacketWorkspace
  defdelegate operator_run_state(session_context, run_id), to: RunState
  defdelegate verification_outcome(session_context, run_id), to: RunState

  def graphql_node_type(value) do
    WorkGraph.graphql_node_type(value) ||
      WorkPackets.graphql_node_type(value) ||
      Runs.graphql_node_type(value)
  end

  def generated_graphql_node(session_context, type, id) do
    [WorkGraph, WorkPackets, Runs]
    |> Enum.reduce_while({:ok, nil}, fn context, {:ok, nil} ->
      case context.graphql_node(session_context, type, id) do
        {:ok, nil} -> {:cont, {:ok, nil}}
        result -> {:halt, result}
      end
    end)
  end
end
