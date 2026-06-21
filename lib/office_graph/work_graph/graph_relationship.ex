defmodule OfficeGraph.WorkGraph.GraphRelationship do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "graph_relationships" do
    field :source_item_id, :binary_id
    field :target_item_id, :binary_id
    field :relationship_type, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:source_item_id, :target_item_id, :relationship_type])
    |> validate_required([:source_item_id, :target_item_id, :relationship_type])
    |> foreign_key_constraint(:source_item_id)
    |> foreign_key_constraint(:target_item_id)
    |> unique_constraint([:source_item_id, :target_item_id, :relationship_type])
  end
end
