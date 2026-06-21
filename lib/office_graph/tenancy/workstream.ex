defmodule OfficeGraph.Tenancy.Workstream do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workstreams" do
    field :name, :string
    field :slug, :string
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :initiative_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(workstream, attrs) do
    workstream
    |> cast(attrs, [:organization_id, :workspace_id, :initiative_id, :name, :slug])
    |> validate_required([:organization_id, :workspace_id, :initiative_id, :name, :slug])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:initiative_id)
    |> unique_constraint([:initiative_id, :slug])
  end
end
