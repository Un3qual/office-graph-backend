defmodule OfficeGraph.Authorization.Capability do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "capabilities" do
    field :key, :string
    field :description, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(capability, attrs) do
    capability
    |> cast(attrs, [:key, :description])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
