defmodule OfficeGraph.AgentRuntime.AdapterState do
  @moduledoc false

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def reset(namespace), do: GenServer.call(__MODULE__, {:reset, namespace})
  def get(namespace, key), do: GenServer.call(__MODULE__, {:get, namespace, key})
  def put(namespace, key, value), do: GenServer.call(__MODULE__, {:put, namespace, key, value})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:reset, namespace}, _from, state),
    do: {:reply, :ok, Map.delete(state, namespace)}

  def handle_call({:get, namespace, key}, _from, state) do
    case get_in(state, [namespace, key]) do
      nil -> {:reply, :error, state}
      value -> {:reply, {:ok, value}, state}
    end
  end

  def handle_call({:put, namespace, key, value}, _from, state) do
    {:reply, :ok, put_in(state, [Access.key(namespace, %{}), key], value)}
  end
end
