defmodule OfficeGraph.Integrations.ExternalSource do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "external_sources" do
    field :key, :string
    field :name, :string
    field :kind, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:key, :name, :kind])
    |> validate_required([:key, :name, :kind])
    |> unique_constraint(:key)
  end
end
