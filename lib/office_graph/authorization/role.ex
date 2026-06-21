defmodule OfficeGraph.Authorization.Role do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "roles" do
    field :organization_id, :binary_id
    field :key, :string
    field :name, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:organization_id, :key, :name])
    |> validate_required([:organization_id, :key, :name])
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:organization_id, :key])
  end
end
