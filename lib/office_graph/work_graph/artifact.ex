defmodule OfficeGraph.WorkGraph.Artifact do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "artifacts" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :graph_item_id, :binary_id
    field :title, :string
    field :uri, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:organization_id, :workspace_id, :graph_item_id, :title, :uri])
    |> validate_required([:organization_id, :workspace_id, :graph_item_id, :title])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:graph_item_id)
    |> unique_constraint(:graph_item_id)
  end
end
