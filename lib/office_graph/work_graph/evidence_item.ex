defmodule OfficeGraph.WorkGraph.EvidenceItem do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "evidence_items" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :graph_item_id, :binary_id
    field :verification_check_id, :binary_id
    field :artifact_id, :binary_id
    field :body_document_id, :binary_id
    field :title, :string
    field :state, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(evidence, attrs) do
    evidence
    |> cast(attrs, [
      :organization_id,
      :workspace_id,
      :graph_item_id,
      :verification_check_id,
      :artifact_id,
      :body_document_id,
      :title,
      :state
    ])
    |> validate_required([
      :organization_id,
      :workspace_id,
      :graph_item_id,
      :verification_check_id,
      :body_document_id,
      :title,
      :state
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:graph_item_id)
    |> foreign_key_constraint(:verification_check_id)
    |> foreign_key_constraint(:artifact_id)
    |> foreign_key_constraint(:body_document_id)
    |> unique_constraint(:graph_item_id)
  end
end
