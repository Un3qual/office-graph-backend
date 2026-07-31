defmodule OfficeGraph.AgentRuntime.ModelManifest do
  @moduledoc """
  Passive model-adapter capability manifest returned by the adapter registry.

  Adapter registration owns validation because it compares manifests with the
  configured adapter contract; this struct names the stable boundary fields.
  """

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
    :token_budget,
    :output_classifications,
    :idempotency_supported,
    :raw_retention,
    :approval_required
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
          token_budget: pos_integer(),
          output_classifications: [atom()],
          idempotency_supported: boolean(),
          raw_retention: false,
          approval_required: boolean()
        }
end
