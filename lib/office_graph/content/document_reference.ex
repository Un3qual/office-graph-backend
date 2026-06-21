defmodule OfficeGraph.Content.DocumentReference do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "document_references" do
    field :document_id, :binary_id
    field :target_type, :string
    field :target_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end
end
