defmodule OfficeGraph.GitHubIntegration.Actions.BindInstallation do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.GitHubIntegration
  alias OfficeGraph.GitHubIntegration.CommandResults.BindInstallation

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    case GitHubIntegration.bind_installation(session_context, input.arguments) do
      {:ok, result} -> BindInstallation.from_result(result)
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end
