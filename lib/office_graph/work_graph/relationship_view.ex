defmodule OfficeGraph.WorkGraph.RelationshipView do
  @moduledoc false

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
    :tombstone_id,
    :source,
    :target
  ]
end
