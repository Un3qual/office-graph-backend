defmodule OfficeGraph.Authorization.RoleAssignment do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "role_assignments" do
    field :principal_id, :binary_id
    field :role_id, :binary_id
    field :organization_id, :binary_id
    field :workspace_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(role_assignment, attrs) do
    role_assignment
    |> cast(attrs, [:principal_id, :role_id, :organization_id, :workspace_id])
    |> validate_required([:principal_id, :role_id, :organization_id])
    |> foreign_key_constraint(:principal_id)
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint([:principal_id, :role_id, :organization_id])
  end
end
