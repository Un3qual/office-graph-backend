defmodule OfficeGraph.Revisions do
  @moduledoc """
  Public boundary for typed revision history.
  """

  use Boundary, deps: [OfficeGraph], exports: []

  require Ash.Query

  alias OfficeGraph.Revisions.Revision

  def record!(operation, resource_type, resource_id, revision_type, summary) do
    Ash.create!(
      Revision,
      %{
        id: Ecto.UUID.generate(),
        operation_id: operation.id,
        resource_type: resource_type,
        resource_id: resource_id,
        revision_type: revision_type,
        summary: summary
      },
      action: :create,
      authorize?: false
    )
  end

  def count_for_operation(operation_id) do
    Revision
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.count!(authorize?: false)
  end
end
