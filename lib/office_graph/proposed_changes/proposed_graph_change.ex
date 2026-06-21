defmodule OfficeGraph.ProposedChanges.ProposedGraphChange do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "proposed_graph_changes" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :operation_id, :binary_id
    field :normalized_event_id, :binary_id
    field :status, :string
    field :change_type, :string
    field :payload, :map, default: %{}
    field :validation_errors, {:array, :string}, default: []
    field :applied_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(change, attrs) do
    change
    |> cast(attrs, [
      :organization_id,
      :workspace_id,
      :operation_id,
      :normalized_event_id,
      :status,
      :change_type,
      :payload,
      :validation_errors,
      :applied_at
    ])
    |> validate_required([
      :organization_id,
      :workspace_id,
      :operation_id,
      :status,
      :change_type,
      :payload,
      :validation_errors
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:normalized_event_id)
  end
end
