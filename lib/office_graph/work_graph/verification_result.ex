defmodule OfficeGraph.WorkGraph.VerificationResult do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "verification_results" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :verification_check_id, :binary_id
    field :evidence_item_id, :binary_id
    field :operation_id, :binary_id
    field :result, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :organization_id,
      :workspace_id,
      :verification_check_id,
      :evidence_item_id,
      :operation_id,
      :result
    ])
    |> validate_required([
      :organization_id,
      :workspace_id,
      :verification_check_id,
      :evidence_item_id,
      :operation_id,
      :result
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:verification_check_id)
    |> foreign_key_constraint(:evidence_item_id)
    |> foreign_key_constraint(:operation_id)
  end
end
