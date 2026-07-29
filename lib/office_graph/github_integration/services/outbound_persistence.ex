defmodule OfficeGraph.GitHubIntegration.OutboundPersistence do
  @moduledoc false

  @callback before_write(atom()) :: :ok | {:error, term()}

  def before_write(stage) when is_atom(stage) do
    implementation().before_write(stage)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :github_outbound_persistence)
  end
end

defmodule OfficeGraph.GitHubIntegration.OutboundPersistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.OutboundPersistence

  @impl true
  def before_write(_stage), do: :ok
end
