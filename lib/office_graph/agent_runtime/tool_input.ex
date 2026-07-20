defmodule OfficeGraph.AgentRuntime.ToolInput do
  @moduledoc false

  @enforce_keys [
    :request_id,
    :execution_id,
    :context_package_id,
    :authority_snapshot_id,
    :operation_id,
    :tool_key,
    :adapter_version,
    :idempotency_key,
    :capability_keys,
    :credential_kinds,
    :timeout_ms,
    :budget_units,
    :sensitivity,
    :external_write,
    :approval_granted?,
    :adapter_payload
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          request_id: Ecto.UUID.t(),
          execution_id: Ecto.UUID.t(),
          context_package_id: Ecto.UUID.t(),
          authority_snapshot_id: Ecto.UUID.t(),
          operation_id: Ecto.UUID.t(),
          tool_key: String.t(),
          adapter_version: String.t(),
          idempotency_key: String.t(),
          capability_keys: [String.t()],
          credential_kinds: [atom()],
          timeout_ms: pos_integer(),
          budget_units: pos_integer(),
          sensitivity: atom(),
          external_write: boolean(),
          approval_granted?: boolean(),
          adapter_payload: map()
        }
end
