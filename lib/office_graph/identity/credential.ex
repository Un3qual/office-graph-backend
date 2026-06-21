defmodule OfficeGraph.Identity.Credential do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "credentials" do
    field :principal_id, :binary_id
    field :provider, :string
    field :subject, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:principal_id, :provider, :subject])
    |> validate_required([:principal_id, :provider, :subject])
    |> foreign_key_constraint(:principal_id)
    |> unique_constraint([:provider, :subject])
  end
end
