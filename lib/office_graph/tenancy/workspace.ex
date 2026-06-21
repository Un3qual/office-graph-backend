defmodule OfficeGraph.Tenancy.Workspace do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workspaces" do
    field :name, :string
    field :slug, :string
    field :organization_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:organization_id, :name, :slug])
    |> validate_required([:organization_id, :name, :slug])
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:organization_id, :slug])
  end
end
