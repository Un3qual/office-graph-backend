defmodule OfficeGraph.Identity.PrincipalProfile do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "principal_profiles" do
    field :principal_id, :binary_id
    field :display_name, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:principal_id, :display_name])
    |> validate_required([:principal_id, :display_name])
    |> foreign_key_constraint(:principal_id)
    |> unique_constraint(:principal_id)
  end
end
