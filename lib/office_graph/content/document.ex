defmodule OfficeGraph.Content.Document do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "documents" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :plain_text, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [:organization_id, :workspace_id, :plain_text])
    |> validate_required([:organization_id, :workspace_id, :plain_text])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
  end
end
