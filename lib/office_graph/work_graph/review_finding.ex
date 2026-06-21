defmodule OfficeGraph.WorkGraph.ReviewFinding do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "review_findings" do
    field :organization_id, :binary_id
    field :workspace_id, :binary_id
    field :graph_item_id, :binary_id
    field :task_id, :binary_id
    field :body_document_id, :binary_id
    field :title, :string
    field :lifecycle_state, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [
      :organization_id,
      :workspace_id,
      :graph_item_id,
      :task_id,
      :body_document_id,
      :title,
      :lifecycle_state
    ])
    |> validate_required([
      :organization_id,
      :workspace_id,
      :graph_item_id,
      :task_id,
      :body_document_id,
      :title,
      :lifecycle_state
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:graph_item_id)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:body_document_id)
    |> unique_constraint(:graph_item_id)
  end
end
