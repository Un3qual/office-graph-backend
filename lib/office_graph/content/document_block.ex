defmodule OfficeGraph.Content.DocumentBlock do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "document_blocks" do
    field :document_id, :binary_id
    field :position, :integer
    field :block_type, :string
    field :text, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:document_id, :position, :block_type, :text])
    |> validate_required([:document_id, :position, :block_type, :text])
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:document_id, :position])
  end
end
