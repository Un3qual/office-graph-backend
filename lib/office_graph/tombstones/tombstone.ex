defmodule OfficeGraph.Tombstones.Tombstone do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tombstones" do
    field :operation_id, :binary_id
    field :resource_type, :string
    field :resource_id, :binary_id
    field :deleted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
