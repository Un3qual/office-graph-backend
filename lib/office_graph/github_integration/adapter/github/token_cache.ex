defmodule OfficeGraph.GitHubIntegration.Adapter.GitHub.TokenCache do
  @moduledoc false

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def fetch(installation_id, app_id) do
    GenServer.call(__MODULE__, {:fetch, installation_id, app_id})
  end

  def put(installation_id, app_id, token, %DateTime{} = expires_at) do
    GenServer.call(
      __MODULE__,
      {:put, installation_id, app_id, token, DateTime.to_unix(expires_at)}
    )
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:fetch, installation_id, app_id}, _from, state) do
    key = {installation_id, app_id}
    now = System.system_time(:second)

    case Map.get(state, key) do
      {token, expires_at} when expires_at > now + 60 ->
        {:reply, {:ok, token}, state}

      _missing_or_expired ->
        {:reply, :miss, Map.delete(state, key)}
    end
  end

  def handle_call({:put, installation_id, app_id, token, expires_at}, _from, state) do
    {:reply, :ok, Map.put(state, {installation_id, app_id}, {token, expires_at})}
  end

  def handle_call(:clear, _from, _state), do: {:reply, :ok, %{}}
end
