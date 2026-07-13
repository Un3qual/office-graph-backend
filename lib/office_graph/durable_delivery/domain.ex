defmodule OfficeGraph.DurableDelivery.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.DurableDelivery.DomainEvent
  end
end
