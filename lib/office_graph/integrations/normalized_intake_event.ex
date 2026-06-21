defmodule OfficeGraph.Integrations.NormalizedIntakeEvent do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "normalized_intake_events" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :raw_archive_id, :binary_id
    field :operation_id, :binary_id
    field :source_identity, :string
    field :replay_identity, :string
    field :outcome, :string
    field :duplicate_of_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :organization_id,
      :workspace_id,
      :raw_archive_id,
      :operation_id,
      :source_identity,
      :replay_identity,
      :outcome,
      :duplicate_of_id
    ])
    |> validate_required([
      :organization_id,
      :workspace_id,
      :raw_archive_id,
      :operation_id,
      :source_identity,
      :replay_identity,
      :outcome
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:raw_archive_id)
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:duplicate_of_id)
  end
end
