defmodule OfficeGraph.AgentRuntime.ModelInput do
  @moduledoc false

  @enforce_keys [
    :request_id,
    :execution_id,
    :context_package_id,
    :authority_snapshot_id,
    :operation_id,
    :adapter_key,
    :adapter_version,
    :idempotency_key,
    :capability_keys,
    :credential_kinds,
    :sensitivity,
    :approval_granted?,
    :timeout_ms,
    :token_budget,
    :fixture_id
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          request_id: Ecto.UUID.t(),
          execution_id: Ecto.UUID.t(),
          context_package_id: Ecto.UUID.t(),
          authority_snapshot_id: Ecto.UUID.t(),
          operation_id: Ecto.UUID.t(),
          adapter_key: String.t(),
          adapter_version: String.t(),
          idempotency_key: String.t(),
          capability_keys: [String.t()],
          credential_kinds: [atom()],
          sensitivity: :public | :internal | :confidential | :restricted,
          approval_granted?: boolean(),
          timeout_ms: pos_integer(),
          token_budget: pos_integer(),
          fixture_id: String.t()
        }
end
