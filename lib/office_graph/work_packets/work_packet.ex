defmodule OfficeGraph.WorkPackets.WorkPacket do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "work_packets" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :title, :string
    field :state, :string

    timestamps(type: :utc_datetime_usec)
  end
end
