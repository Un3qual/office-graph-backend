defmodule OfficeGraph.AgentRuntime.Actions.CancelAgentExecution do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.AgentRuntime
  alias OfficeGraph.AgentRuntime.CommandResults.ExecutionMutation
  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :agent_cancel,
             idempotency_key,
             command_input
           ),
         {:ok, result} <-
           AgentRuntime.cancel_execution(session_context, operation, command_input) do
      ExecutionMutation.from_cancellation(operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
