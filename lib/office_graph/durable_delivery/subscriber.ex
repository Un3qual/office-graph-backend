defmodule OfficeGraph.DurableDelivery.Subscriber do
  @moduledoc false

  use GenServer, restart: :temporary

  alias OfficeGraph.DurableDelivery.Subscriptions

  @registry OfficeGraph.DurableDelivery.SubscriptionRegistry

  def start_link(opts) do
    name = {:via, Registry, {@registry, subscription_key(opts)}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def refresh(pid, session_context) do
    GenServer.call(pid, {:refresh, session_context})
  catch
    :exit, _reason -> {:error, :subscription_unavailable}
  end

  @impl GenServer
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    organization_id = Keyword.fetch!(opts, :organization_id)
    workspace_id = Keyword.fetch!(opts, :workspace_id)

    :ok = Subscriptions.subscribe_topic(organization_id, workspace_id)

    {:ok,
     %{
       owner: owner,
       owner_monitor: Process.monitor(owner),
       session_context: Keyword.fetch!(opts, :session_context),
       organization_id: organization_id,
       workspace_id: workspace_id
     }}
  end

  @impl GenServer
  def handle_call({:refresh, session_context}, _from, state) do
    {:reply, :ok, %{state | session_context: session_context}}
  end

  @impl GenServer
  def handle_info(
        {:projection_invalidated, %{organization_id: organization_id, workspace_id: workspace_id}} =
          message,
        %{organization_id: organization_id, workspace_id: workspace_id} = state
      ) do
    case Subscriptions.authorize(
           state.session_context,
           state.organization_id,
           state.workspace_id
         ) do
      :ok ->
        send(state.owner, message)
        {:noreply, state}

      {:error, :forbidden} ->
        {:stop, :normal, state}
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, owner, _reason},
        %{owner_monitor: monitor, owner: owner} = state
      ) do
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp subscription_key(opts) do
    {
      Keyword.fetch!(opts, :owner),
      Keyword.fetch!(opts, :organization_id),
      Keyword.fetch!(opts, :workspace_id)
    }
  end
end
