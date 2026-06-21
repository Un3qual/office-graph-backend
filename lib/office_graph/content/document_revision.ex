defmodule OfficeGraph.Content.DocumentRevision do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "document_revisions" do
    field :document_id, :binary_id
    field :operation_id, :binary_id
    field :revision_number, :integer
    field :semantic_summary, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:document_id, :operation_id, :revision_number, :semantic_summary])
    |> validate_required([:document_id, :operation_id, :revision_number, :semantic_summary])
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:operation_id)
    |> unique_constraint([:document_id, :revision_number])
  end
end
