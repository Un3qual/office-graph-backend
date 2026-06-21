defmodule OfficeGraph.Identity.Session do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sessions" do
    field :principal_id, :binary_id
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :purpose, :string
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:principal_id, :organization_id, :workspace_id, :purpose, :revoked_at])
    |> validate_required([:principal_id, :organization_id, :workspace_id, :purpose])
    |> foreign_key_constraint(:principal_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint([:principal_id, :organization_id, :workspace_id, :purpose])
  end
end
