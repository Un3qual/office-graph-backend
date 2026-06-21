defmodule OfficeGraph.Authorization.RoleCapability do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "role_capabilities" do
    field :role_id, :binary_id
    field :capability_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(role_capability, attrs) do
    role_capability
    |> cast(attrs, [:role_id, :capability_id])
    |> validate_required([:role_id, :capability_id])
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:capability_id)
    |> unique_constraint([:role_id, :capability_id])
  end
end
