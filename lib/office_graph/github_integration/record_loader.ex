defmodule OfficeGraph.GitHubIntegration.RecordLoader do
  @moduledoc false

  @callback get(module(), term(), keyword()) :: {:ok, struct() | nil} | {:error, term()}
  @callback read_one(module(), Ash.Query.t(), keyword()) ::
              {:ok, struct() | nil} | {:error, term()}
  @callback read(module(), Ash.Query.t(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  @callback aggregate(module(), Ash.Query.t(), list(), keyword()) ::
              {:ok, map()} | {:error, term()}

  def get(resource, id, opts) do
    implementation().get(resource, id, opts)
  end

  def read_one(resource, query, opts) do
    implementation().read_one(resource, query, opts)
  end

  def read(resource, query, opts) do
    implementation().read(resource, query, opts)
  end

  def aggregate(resource, query, aggregates, opts) do
    implementation().aggregate(resource, query, aggregates, opts)
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

  @impl true
  def read(_resource, query, opts), do: Ash.read(query, opts)

  @impl true
  def aggregate(_resource, query, aggregates, opts),
    do: Ash.aggregate(query, aggregates, opts)
end
