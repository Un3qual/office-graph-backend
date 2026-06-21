defmodule OfficeGraph.Revisions do
  @moduledoc """
  Public boundary for typed revision history.
  """

  use Boundary, deps: [OfficeGraph.Repo], exports: []

  import Ecto.Query

  alias OfficeGraph.Repo
  alias OfficeGraph.Revisions.Revision

  def record!(operation, resource_type, resource_id, revision_type, summary) do
    %Revision{}
    |> Revision.changeset(%{
      operation_id: operation.id,
      resource_type: resource_type,
      resource_id: resource_id,
      revision_type: revision_type,
      summary: summary
    })
    |> Repo.insert!()
  end

  def count_for_operation(operation_id) do
    Revision
    |> where([revision], revision.operation_id == ^operation_id)
    |> Repo.aggregate(:count)
  end
end
