defmodule OfficeGraph.AgentRuntime.ToolManifest do
  @moduledoc false

  @enforce_keys [
    :key,
    :version,
    :input_schema,
    :output_schema,
    :capability_keys,
    :credential_kinds,
    :sensitivity,
    :external_write,
    :timeout_ms,
    :budget_units,
    :output_classifications,
    :idempotency_supported,
    :raw_retention
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          key: String.t(),
          version: String.t(),
          input_schema: map(),
          output_schema: map(),
          capability_keys: [String.t()],
          credential_kinds: [atom()],
          sensitivity: atom(),
          external_write: false,
          timeout_ms: pos_integer(),
          budget_units: pos_integer(),
          output_classifications: [atom()],
          idempotency_supported: boolean(),
          raw_retention: false
        }
end
