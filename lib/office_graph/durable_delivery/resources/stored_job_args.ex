defmodule OfficeGraph.DurableDelivery.StoredJobArgs do
  @moduledoc false

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  attributes do
    attribute :event_id, :string, public?: true
    attribute :organization_id, :uuid, public?: true
    attribute :workspace_id, :uuid, public?: true
  end
end
