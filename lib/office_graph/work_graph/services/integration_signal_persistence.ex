defmodule OfficeGraph.WorkGraph.IntegrationSignalPersistence do
  @moduledoc false

  @callback checkpoint(atom()) :: :ok | {:error, term()}

  def checkpoint(stage) when is_atom(stage) do
    implementation().checkpoint(stage)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :integration_signal_persistence)
  end
end

defmodule OfficeGraph.WorkGraph.IntegrationSignalPersistence.Default do
  @moduledoc false

  @behaviour OfficeGraph.WorkGraph.IntegrationSignalPersistence

  @impl true
  def checkpoint(_stage), do: :ok
end
