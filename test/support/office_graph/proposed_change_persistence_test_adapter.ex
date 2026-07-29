defmodule OfficeGraph.ProposedChanges.PersistenceTestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.ProposedChanges.Persistence

  @adapter_key :proposed_change_persistence
  @callbacks_key :proposed_change_persistence_test_callbacks

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

  def clear! do
    Application.put_env(:office_graph, @callbacks_key, %{})
    :ok
  end

  @impl true
  def before_write(stage, context) do
    case Application.fetch_env!(:office_graph, @callbacks_key) do
      %{^stage => callback} when is_function(callback, 1) -> callback.(context)
      %{^stage => response} -> response
      _callbacks -> :ok
    end
  end

  defp restore(key, {:ok, value}), do: Application.put_env(:office_graph, key, value)
  defp restore(key, :error), do: Application.delete_env(:office_graph, key)
end
