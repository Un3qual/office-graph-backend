defmodule OfficeGraph.DurableDelivery.Subscriptions do
  @moduledoc false

  alias OfficeGraph.{Authorization, Identity}

  def subscribe(session_context, organization_id, workspace_id) do
    with :ok <- Identity.validate_session_context(session_context),
         true <- session_context.organization_id == organization_id,
         true <- session_context.workspace_id == workspace_id,
         :ok <-
           Authorization.authorize_projection(session_context, :durable_delivery_read,
             organization_id: organization_id
           ) do
      Phoenix.PubSub.subscribe(OfficeGraph.PubSub, topic(organization_id, workspace_id))
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

  defp topic(organization_id, workspace_id) do
    "projection-invalidation:#{organization_id}:#{workspace_id}"
  end
end
