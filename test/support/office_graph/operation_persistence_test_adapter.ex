defmodule OfficeGraph.Operations.PersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Operations.Persistence

  @adapter_key :operation_persistence
  @responses_key :operation_persistence_test_responses

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

  @impl true
  def before_write(stage) do
    case Application.fetch_env!(:office_graph, @responses_key) do
      %{^stage => response} -> response
      _responses -> :ok
    end
  end

  defp restore(key, {:ok, value}), do: Application.put_env(:office_graph, key, value)
  defp restore(key, :error), do: Application.delete_env(:office_graph, key)
end
