defmodule OfficeGraph.DurableDelivery.ResourceContractTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.DurableDelivery.DomainEvent

  test "operation replay lookup exposes a declarative operation access path" do
    assert %AshPostgres.CustomIndex{
             fields: [:operation_id],
             unique: false
           } =
             Enum.find(
               AshPostgres.DataLayer.Info.custom_indexes(DomainEvent),
               &(&1.name == "domain_events_operation_id_index")
             )
  end
end
