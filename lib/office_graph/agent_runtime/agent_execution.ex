defmodule OfficeGraph.AgentRuntime.AgentExecution do
  @moduledoc false

  @lifecycle_states ~w(queued running waiting_approval waiting_context retry_scheduled completed failed cancelled)
  @non_terminal_states ~w(queued running waiting_approval waiting_context retry_scheduled)

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_executions"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_operation: "agent_executions_operation_index",
                         unique_binding_run_idempotency:
                           "agent_executions_binding_run_idempotency_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :definition_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_binding_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :run_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :agent_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :delegator_principal_id, :uuid, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :invocation_mode, :string, allow_nil?: false, public?: true
    attribute :origin, :string, allow_nil?: false, public?: true
    attribute :requested_outcome, :string, allow_nil?: false, public?: true
    attribute :autonomy_mode, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    attribute :state_version, :integer,
      allow_nil?: false,
      default: 1,
      constraints: [min: 1],
      public?: true

    attribute :current_step_key, :string, public?: true

    attribute :attempt_count, :integer,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0],
      public?: true

    attribute :idempotency_key, :string, allow_nil?: false, public?: true
    attribute :failure_code, :string, public?: true
    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true
    attribute :cancelled_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
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
        :definition_id,
        :organization_binding_id,
        :organization_id,
        :workspace_id,
        :run_id,
        :graph_item_id,
        :agent_principal_id,
        :delegator_principal_id,
        :operation_id,
        :invocation_mode,
        :origin,
        :requested_outcome,
        :autonomy_mode,
        :state,
        :state_version,
        :current_step_key,
        :attempt_count,
        :idempotency_key,
        :failure_code,
        :started_at,
        :completed_at,
        :cancelled_at
      ]

      validate one_of(:invocation_mode, ~w(human automatic))
      validate one_of(:origin, ~w(operator system_trigger))
      validate one_of(:state, @lifecycle_states)
    end

    update :transition do
      public? false
      require_atomic? false

      accept [
        :state,
        :current_step_key,
        :attempt_count,
        :failure_code,
        :started_at,
        :completed_at,
        :cancelled_at
      ]

      validate data_one_of(:state, @non_terminal_states)
      validate one_of(:state, @lifecycle_states)
      change optimistic_lock(:state_version)
    end
  end

  identities do
    identity :unique_operation, [:operation_id]

    identity :unique_binding_run_idempotency, [
      :organization_binding_id,
      :run_id,
      :idempotency_key
    ]
  end

  relationships do
    belongs_to :definition, OfficeGraph.AgentRuntime.AgentDefinition do
      source_attribute :definition_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :organization_binding, OfficeGraph.AgentRuntime.OrganizationBinding do
      source_attribute :organization_binding_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :run, OfficeGraph.Runs.Run do
      source_attribute :run_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :graph_item_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :agent_principal, OfficeGraph.Identity.Principal do
      source_attribute :agent_principal_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :delegator_principal, OfficeGraph.Identity.Principal do
      source_attribute :delegator_principal_id
      define_attribute? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end
  end
end
