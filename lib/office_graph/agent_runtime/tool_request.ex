defmodule OfficeGraph.AgentRuntime.ToolRequest do
  @moduledoc false

  @states ~w(pending running succeeded retry_scheduled failed cancelled)

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_tool_requests"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_execution_step_idempotency:
                           "agent_tool_requests_execution_step_idempotency_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :execution_id, :uuid, allow_nil?: false, public?: true
    attribute :context_package_id, :uuid, allow_nil?: false, public?: true
    attribute :authority_snapshot_id, :uuid, allow_nil?: false, public?: true
    attribute :credential_id, :uuid, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :step_key, :string, allow_nil?: false, public?: true
    attribute :tool_key, :string, allow_nil?: false, public?: true
    attribute :adapter_version, :string, allow_nil?: false, public?: true
    attribute :idempotency_key, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true
    attribute :sensitivity, :string, allow_nil?: false, public?: true
    attribute :external_write, :boolean, allow_nil?: false, default: false, public?: true
    attribute :timeout_ms, :integer, allow_nil?: false, constraints: [min: 1], public?: true
    attribute :budget_units, :integer, allow_nil?: false, constraints: [min: 1], public?: true
    attribute :input_hash, :string, allow_nil?: false, public?: true
    attribute :output_hash, :string, public?: true
    attribute :output_classification, :string, public?: true
    attribute :output_reference, :string, public?: true
    attribute :output_content_hash, :string, public?: true
    attribute :output_byte_count, :integer, constraints: [min: 1], public?: true
    attribute :failure_code, :string, public?: true
    attribute :requested_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :execution_id,
        :context_package_id,
        :authority_snapshot_id,
        :credential_id,
        :operation_id,
        :step_key,
        :tool_key,
        :adapter_version,
        :idempotency_key,
        :state,
        :sensitivity,
        :external_write,
        :timeout_ms,
        :budget_units,
        :input_hash,
        :output_hash,
        :output_classification,
        :failure_code,
        :requested_at,
        :completed_at
      ]

      validate one_of(:state, @states)
      validate attribute_equals(:external_write, false)
    end

    update :record_result do
      public? false

      accept [
        :state,
        :output_hash,
        :output_classification,
        :output_reference,
        :output_content_hash,
        :output_byte_count,
        :failure_code,
        :completed_at
      ]

      validate one_of(:state, @states)
    end
  end

  identities do
    identity :unique_execution_step_idempotency, [:execution_id, :step_key, :idempotency_key]
  end

  relationships do
    belongs_to :execution, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :execution_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :context_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :context_package_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :authority_snapshot, OfficeGraph.AgentRuntime.AuthoritySnapshot do
      source_attribute :authority_snapshot_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :credential, OfficeGraph.Integrations.IntegrationCredential do
      source_attribute :credential_id
      define_attribute? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end
  end
end
