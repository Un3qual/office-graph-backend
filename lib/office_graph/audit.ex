defmodule OfficeGraph.Audit do
  @moduledoc """
  Public boundary for audit record creation and retrieval.
  """

  use Boundary, deps: [OfficeGraph.Repo], exports: []

  import Ecto.Query

  alias OfficeGraph.Audit.AuditRecord
  alias OfficeGraph.Repo

  def record!(operation, action, resource_type, resource_id, sensitive? \\ true) do
    %AuditRecord{}
    |> AuditRecord.changeset(%{
      operation_id: operation.id,
      actor_principal_id: operation.principal_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      sensitive: sensitive?
    })
    |> Repo.insert!()
  end

  def count_for_operation(operation_id) do
    AuditRecord
    |> where([record], record.operation_id == ^operation_id)
    |> Repo.aggregate(:count)
  end
end
