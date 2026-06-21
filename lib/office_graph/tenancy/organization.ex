defmodule OfficeGraph.Tenancy.Organization do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "organizations" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
