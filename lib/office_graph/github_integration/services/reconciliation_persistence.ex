defmodule OfficeGraph.GitHubIntegration.ReconciliationPersistence do
  @moduledoc false

  @callback before_write(atom()) :: :ok | {:error, term()}

  def before_write(stage) when is_atom(stage) do
    implementation().before_write(stage)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :github_reconciliation_persistence)
  end
end

defmodule OfficeGraph.GitHubIntegration.ReconciliationPersistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.ReconciliationPersistence

  @impl true
  def before_write(_stage), do: :ok
end
