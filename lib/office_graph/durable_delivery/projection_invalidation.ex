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
end
