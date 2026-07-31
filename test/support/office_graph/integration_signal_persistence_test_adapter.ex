defmodule OfficeGraph.WorkGraph.IntegrationSignalPersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.WorkGraph.IntegrationSignalPersistence

  alias OfficeGraphTest.PersistenceFailureResponses

  def configure!(responses),
    do: PersistenceFailureResponses.configure!(:integration_signal, responses)

  def clear!, do: PersistenceFailureResponses.clear!(:integration_signal)

  @impl true
  def checkpoint(stage) do
    case PersistenceFailureResponses.fetch(:integration_signal, stage) do
      :unavailable -> {:error, :integration_storage_unavailable}
      response -> response
    end
  end
end
