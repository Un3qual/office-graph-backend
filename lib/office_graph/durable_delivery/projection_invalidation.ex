defmodule OfficeGraph.DurableDelivery.ProjectionInvalidation do
  @moduledoc """
  Scope-bound identity and version hint for authoritative projection refetches.
  """

  @enforce_keys [
    :event_id,
    :event_kind,
    :subject_kind,
    :subject_id,
    :subject_version,
    :operation_id,
    :organization_id,
    :workspace_id
  ]
  defstruct @enforce_keys

  def from_event(event) do
    struct!(__MODULE__,
      event_id: event.id,
      event_kind: event.event_kind,
      subject_kind: event.subject_kind,
      subject_id: event.subject_id,
      subject_version: event.subject_version,
      operation_id: event.operation_id,
      organization_id: event.organization_id,
      workspace_id: event.workspace_id
    )
  end
end
