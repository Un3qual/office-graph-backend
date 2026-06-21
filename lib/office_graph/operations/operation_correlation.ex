defmodule OfficeGraph.Operations.OperationCorrelation do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "operation_correlations" do
    field :principal_id, :binary_id
    field :session_id, :binary_id
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :action, :string
    field :correlation_id, :string
    field :idempotency_key, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(operation, attrs) do
    operation
    |> cast(attrs, [
      :principal_id,
      :session_id,
      :organization_id,
      :workspace_id,
      :action,
      :correlation_id,
      :idempotency_key,
      :metadata
    ])
    |> validate_required([
      :principal_id,
      :session_id,
      :organization_id,
      :workspace_id,
      :action,
      :correlation_id
    ])
    |> foreign_key_constraint(:principal_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint(:correlation_id)
  end
end
