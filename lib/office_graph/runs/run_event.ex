defmodule OfficeGraph.Runs.RunEvent do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "run_events" do
    field :run_id, :binary_id
    field :event_type, :string
    field :payload, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end
end
