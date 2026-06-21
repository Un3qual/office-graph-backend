defmodule OfficeGraph.ExternalRefs.ExternalReference do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "external_references" do
    field :source_id, :binary_id
    field :external_id, :string
    field :resource_type, :string
    field :resource_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end
end
