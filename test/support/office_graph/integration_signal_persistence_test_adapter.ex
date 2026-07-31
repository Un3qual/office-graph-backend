defmodule OfficeGraph.WorkGraph.IntegrationSignalPersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.WorkGraph.IntegrationSignalPersistence

  @adapter_key :integration_signal_persistence
  @responses_key :integration_signal_persistence_test_responses

  def configure!(responses) when is_list(responses) do
    configured_adapter = Application.fetch_env(:office_graph, @adapter_key)
    configured_responses = Application.fetch_env(:office_graph, @responses_key)

    Application.put_env(:office_graph, @adapter_key, __MODULE__)
    Application.put_env(:office_graph, @responses_key, Map.new(responses))

    ExUnit.Callbacks.on_exit(fn ->
      restore(@adapter_key, configured_adapter)
      restore(@responses_key, configured_responses)
    end)

    :ok
  end

  def clear! do
    Application.put_env(:office_graph, @responses_key, %{})
    :ok
  end

  @impl true
  def checkpoint(stage) do
    case Application.fetch_env!(:office_graph, @responses_key) do
      %{^stage => :unavailable} -> {:error, :integration_storage_unavailable}
      %{^stage => response} -> response
      _responses -> :ok
    end
  end

  defp restore(key, {:ok, value}), do: Application.put_env(:office_graph, key, value)
  defp restore(key, :error), do: Application.delete_env(:office_graph, key)
end
