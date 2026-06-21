defmodule OfficeGraph.Content.DocumentMark do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "document_marks" do
    field :block_id, :binary_id
    field :mark_type, :string
    field :attrs, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end
end
