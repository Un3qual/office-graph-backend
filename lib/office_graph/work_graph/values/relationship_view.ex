defmodule OfficeGraph.WorkGraph.RelationshipView do
  @moduledoc """
  Passive authorization-filtered relationship projection returned to API readers.

  `OfficeGraph.WorkGraph.Queries` owns assembly because it must redact endpoints
  according to the current caller's scope.
  """

  @enforce_keys [
    :id,
    :definition_key,
    :family,
    :direction,
    :lifecycle,
    :governing_workspace_id,
    :valid_from,
    :operation_id,
    :source,
    :target
  ]

  defstruct [
    :id,
    :definition_key,
    :family,
    :direction,
    :lifecycle,
    :governing_workspace_id,
    :valid_from,
    :valid_until,
    :operation_id,
    :run_id,
    :integration_event_id,
    :supersedes_relationship_id,
    :deletion_operation_id,
    :deleted_by_principal_id,
    :deleted_at,
    :deletion_reason,
    :source,
    :target
  ]
end
