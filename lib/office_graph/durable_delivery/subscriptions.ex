defmodule OfficeGraph.DurableDelivery.Subscriptions do
  @moduledoc false

  alias OfficeGraph.{Authorization, Identity}
  alias OfficeGraph.DurableDelivery.Subscriber

  @subscription_supervisor OfficeGraph.DurableDelivery.SubscriptionSupervisor

  def subscribe(session_context, organization_id, workspace_id) do
    with :ok <- authorize(session_context, organization_id, workspace_id) do
      start_subscriber(session_context, organization_id, workspace_id)
    else
      _other -> {:error, :forbidden}
    end
  end

  def authorize(session_context, organization_id, workspace_id) do
    with :ok <- Identity.validate_session_context(session_context),
         true <- session_context.organization_id == organization_id,
         true <- session_context.workspace_id == workspace_id,
         :ok <-
           Authorization.authorize(session_context, :durable_delivery_read,
             organization_id: organization_id
           ) do
      :ok
    else
      _other -> {:error, :forbidden}
    end
  end

  def broadcast(%{organization_id: organization_id, workspace_id: workspace_id} = invalidation) do
    Phoenix.PubSub.broadcast(
      OfficeGraph.PubSub,
      topic(organization_id, workspace_id),
      {:projection_invalidated, invalidation}
    )
  end

  def subscribe_topic(organization_id, workspace_id) do
    Phoenix.PubSub.subscribe(OfficeGraph.PubSub, topic(organization_id, workspace_id))
  end

  def topic(organization_id, workspace_id) do
    "projection-invalidation:#{organization_id}:#{workspace_id}"
  end

  defp start_subscriber(session_context, organization_id, workspace_id) do
    child =
      {Subscriber,
       owner: self(),
       session_context: session_context,
       organization_id: organization_id,
       workspace_id: workspace_id}

    case DynamicSupervisor.start_child(@subscription_supervisor, child) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, _error} -> {:error, :subscription_unavailable}
    end
  end
end
