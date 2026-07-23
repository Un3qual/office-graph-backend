defmodule OfficeGraph.Projections do
  @moduledoc """
  Public boundary for authorization-filtered graph projections.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Audit,
      OfficeGraph.ExternalRefs,
      OfficeGraph.GitHubIntegration,
      OfficeGraph.Integrations,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Revisions,
      OfficeGraph.Runs,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph,
      OfficeGraph.WorkPackets
    ],
    exports: [CommandAffordance]

  alias OfficeGraph.Projections.{
    AgentContext,
    OperatorWorkflow,
    PacketReadiness,
    PacketWorkspace,
    RunIndex,
    RunState
  }

  alias OfficeGraph.{Runs, WorkGraph, WorkPackets}

  defdelegate operator_inbox(session_context), to: OperatorWorkflow
  defdelegate operator_inbox(session_context, opts), to: OperatorWorkflow
  defdelegate operator_workflow_items_page(session_context, opts), to: OperatorWorkflow
  defdelegate operator_workflow_item(session_context, normalized_event_id), to: OperatorWorkflow

  defdelegate operator_relationship_details_page(session_context, normalized_event_id, opts),
    to: OperatorWorkflow,
    as: :relationship_details_page

  defdelegate manual_intake_affordance(session_context), to: OperatorWorkflow
  defdelegate packet_readiness(session_context, attrs), to: PacketReadiness
  defdelegate packet_workspace(session_context, packet_id), to: PacketWorkspace

  defdelegate packet_version_history_page(session_context, packet_id, opts),
    to: PacketWorkspace,
    as: :version_history_page

  defdelegate packet_create_affordance(session_context), to: PacketWorkspace
  defdelegate operator_run_state(session_context, run_id), to: RunState
  defdelegate operator_runs_page(session_context, opts), to: RunIndex, as: :page

  defdelegate operator_run_activity_page(session_context, run_id, opts),
    to: RunState,
    as: :activity_page

  defdelegate operator_run_command_option_page(session_context, run_id, kind, opts),
    to: RunState,
    as: :command_option_page

  defdelegate verification_outcome(session_context, run_id), to: RunState

  defdelegate agent_context(authority, graph_item_id, run_id), to: AgentContext, as: :project

  defdelegate integration_health(session_context, installation_id, opts \\ []),
    to: OfficeGraph.GitHubIntegration

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
