defmodule OfficeGraph.AgentRuntime.Actions.ResolveAgentApproval do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.AgentRuntime
  alias OfficeGraph.AgentRuntime.CommandResults.ApprovalResolution
  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :agent_approval_resolve,
             idempotency_key,
             command_input
           ),
         {:ok, result} <- resolve(session_context, operation, command_input) do
      ApprovalResolution.from_result(operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}

  defp resolve(session_context, operation, attrs) do
    case attrs.decision do
      "approved" ->
        AgentRuntime.approve(
          session_context,
          operation,
          attrs.approval_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )

      "denied" ->
        AgentRuntime.deny_approval(
          session_context,
          operation,
          attrs.approval_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )

      "cancelled" ->
        AgentRuntime.cancel_approval(
          session_context,
          operation,
          attrs.approval_request_id,
          attrs.expected_version,
          attrs.resolution_reason
        )
    end
  end
end
