defmodule OfficeGraph.WorkGraph.VerificationCheck do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "verification_checks" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :graph_item_id, :binary_id
    field :review_finding_id, :binary_id
    field :description_document_id, :binary_id
    field :title, :string
    field :lifecycle_state, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(check, attrs) do
    check
    |> cast(attrs, [
      :organization_id,
      :workspace_id,
      :graph_item_id,
      :review_finding_id,
      :description_document_id,
      :title,
      :lifecycle_state
    ])
    |> validate_required([
      :organization_id,
      :workspace_id,
      :graph_item_id,
      :review_finding_id,
      :description_document_id,
      :title,
      :lifecycle_state
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:graph_item_id)
    |> foreign_key_constraint(:review_finding_id)
    |> foreign_key_constraint(:description_document_id)
    |> unique_constraint(:graph_item_id)
  end
end
