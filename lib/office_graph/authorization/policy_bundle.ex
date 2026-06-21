defmodule OfficeGraph.Authorization.PolicyBundle do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "policy_bundles" do
    field :organization_id, :binary_id
    field :version, :integer
    field :status, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(policy_bundle, attrs) do
    policy_bundle
    |> cast(attrs, [:organization_id, :version, :status])
    |> validate_required([:organization_id, :version, :status])
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:organization_id, :version])
  end
end
