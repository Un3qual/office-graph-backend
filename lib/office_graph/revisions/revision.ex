defmodule OfficeGraph.Revisions.Revision do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "revisions" do
    field :operation_id, :binary_id
    field :resource_type, :string
    field :resource_id, :binary_id
    field :revision_type, :string
    field :summary, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:operation_id, :resource_type, :resource_id, :revision_type, :summary])
    |> validate_required([:operation_id, :resource_type, :resource_id, :revision_type])
    |> foreign_key_constraint(:operation_id)
  end
end
