defmodule OfficeGraph.Tenancy.Initiative do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "initiatives" do
    field :name, :string
    field :slug, :string
    field :organization_id, :binary_id
    field :workspace_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(initiative, attrs) do
    initiative
    |> cast(attrs, [:organization_id, :workspace_id, :name, :slug])
    |> validate_required([:organization_id, :workspace_id, :name, :slug])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint([:workspace_id, :slug])
  end
end
