defmodule OfficeGraph.WorkGraph.GraphItem do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "graph_items" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :resource_type, :string
    field :resource_id, :binary_id
    field :title, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:organization_id, :workspace_id, :resource_type, :resource_id, :title])
    |> validate_required([:organization_id, :workspace_id, :resource_type, :resource_id, :title])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint([:resource_type, :resource_id])
  end
end
