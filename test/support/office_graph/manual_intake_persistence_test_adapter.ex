defmodule OfficeGraph.Integrations.ManualIntakePersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.Integrations.ManualIntakePersistence

  @adapter_key :manual_intake_persistence
  @callbacks_key :manual_intake_persistence_test_callbacks

  def configure!(callbacks) when is_list(callbacks) do
    configured_adapter = Application.fetch_env(:office_graph, @adapter_key)
    configured_callbacks = Application.fetch_env(:office_graph, @callbacks_key)

    Application.put_env(:office_graph, @adapter_key, __MODULE__)
    Application.put_env(:office_graph, @callbacks_key, Map.new(callbacks))

    ExUnit.Callbacks.on_exit(fn ->
      restore(@adapter_key, configured_adapter)
      restore(@callbacks_key, configured_callbacks)
    end)

    :ok
  end

  @impl true
  def before_write(stage, attrs) do
    case Application.fetch_env!(:office_graph, @callbacks_key) do
      %{^stage => callback} when is_function(callback, 1) -> callback.(attrs)
      %{^stage => response} -> response
      _callbacks -> :ok
    end
  end

  defp restore(key, {:ok, value}), do: Application.put_env(:office_graph, key, value)
  defp restore(key, :error), do: Application.delete_env(:office_graph, key)
end
