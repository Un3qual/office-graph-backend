defmodule OfficeGraph.Runs.Run do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "runs" do
    field :work_packet_id, :binary_id
    field :state, :string

    timestamps(type: :utc_datetime_usec)
  end
end
