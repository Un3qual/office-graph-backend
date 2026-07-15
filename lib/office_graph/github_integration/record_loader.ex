defmodule OfficeGraph.GitHubIntegration.RecordLoader do
  @moduledoc false

  @callback get(module(), term(), keyword()) :: {:ok, struct() | nil} | {:error, term()}
  @callback read_one(module(), Ash.Query.t(), keyword()) ::
              {:ok, struct() | nil} | {:error, term()}

  def get(resource, id, opts) do
    implementation().get(resource, id, opts)
  end

  def read_one(resource, query, opts) do
    implementation().read_one(resource, query, opts)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :github_record_loader)
  end
end

defmodule OfficeGraph.GitHubIntegration.RecordLoader.AshAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.RecordLoader

  @impl true
  def get(resource, id, opts), do: Ash.get(resource, id, opts)

  @impl true
  def read_one(_resource, query, opts), do: Ash.read_one(query, opts)
end
