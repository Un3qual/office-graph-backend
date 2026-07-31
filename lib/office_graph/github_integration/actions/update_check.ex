defmodule OfficeGraph.GitHubIntegration.Actions.UpdateCheck do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.GitHubIntegration
  alias OfficeGraph.GitHubIntegration.CommandResults.OutboundAction
  alias OfficeGraph.Operations

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, attrs} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :github_check_update,
             idempotency_key,
             attrs
           ),
         {:ok, action} <- GitHubIntegration.update_check(session_context, operation, attrs) do
      OutboundAction.from_result("update_github_check", operation, action)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
