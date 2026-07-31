defmodule OfficeGraph.GitHubIntegration.InstallationBindingStore do
  @moduledoc false

  @callback persist(Ash.ActionInput.t(), keyword()) ::
              {:ok, term()} | {:error, term()}

  def persist(input, opts) do
    implementation().persist(input, opts)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :github_installation_binding_store)
  end
end

defmodule OfficeGraph.GitHubIntegration.InstallationBindingStore.AshAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.InstallationBindingStore

  @impl true
  def persist(input, opts), do: Ash.run_action(input, opts)
end
