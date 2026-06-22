defmodule OfficeGraph.Audit do
  @moduledoc """
  Public boundary for audit record creation and retrieval.
  """

  use Boundary, deps: [OfficeGraph], exports: []

  require Ash.Query

  alias OfficeGraph.Audit.AuditRecord

  def record!(operation, action, resource_type, resource_id, sensitive? \\ true) do
    Ash.create!(
      AuditRecord,
      %{
        id: Ecto.UUID.generate(),
        operation_id: operation.id,
        actor_principal_id: operation.principal_id,
        action: action,
        resource_type: resource_type,
        resource_id: resource_id,
        sensitive: sensitive?
      },
      action: :create,
      authorize?: false,
      return_notifications?: true
    )
    |> record_without_notifications()
  end

  def count_for_operation(operation_id) do
    AuditRecord
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.count!(authorize?: false)
  end

  defp record_without_notifications({record, _notifications}), do: record
  defp record_without_notifications(record), do: record
end
