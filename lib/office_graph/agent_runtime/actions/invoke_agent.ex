defmodule OfficeGraph.AgentRuntime.Actions.InvokeAgent do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.AgentRuntime
  alias OfficeGraph.AgentRuntime.CommandResults.ExecutionMutation
  alias OfficeGraph.CommandSupport.CommandError

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    case AgentRuntime.invoke_human(session_context, input.arguments) do
      {:ok, result} -> ExecutionMutation.from_invocation(result)
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
