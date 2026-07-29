defmodule OfficeGraph.DurableDelivery.StoredJobMeta do
  @moduledoc false

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  attributes do
    attribute :terminal_failure_code, :string, public?: true
  end
end
