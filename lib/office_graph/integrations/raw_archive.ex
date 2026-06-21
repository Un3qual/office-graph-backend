defmodule OfficeGraph.Integrations.RawArchive do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "raw_archives" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :source_id, :binary_id
    field :operation_id, :binary_id
    field :content_hash, :string
    field :body, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(raw_archive, attrs) do
    raw_archive
    |> cast(attrs, [
      :organization_id,
      :workspace_id,
      :source_id,
      :operation_id,
      :content_hash,
      :body,
      :metadata
    ])
    |> validate_required([
      :organization_id,
      :workspace_id,
      :source_id,
      :operation_id,
      :content_hash,
      :body
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:operation_id)
  end
end
