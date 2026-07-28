defmodule OfficeGraph.AgentRuntime.AgentExecution do
  @moduledoc false

  @lifecycle_states ~w(queued running waiting_approval waiting_context retry_scheduled completed failed cancelled)
  @non_terminal_states ~w(queued running waiting_approval waiting_context retry_scheduled)

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "agent_executions"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_operation: "agent_executions_operation_index",
                         unique_binding_run_idempotency:
                           "agent_executions_binding_run_idempotency_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

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
    attribute :lease_token, :string
    attribute :lease_expires_at, :utc_datetime_usec, public?: true

    attribute :attempt_count, :integer,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0],
      public?: true

    attribute :idempotency_key, :string, allow_nil?: false
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
      public? true
      pagination keyset?: true, countable: false, required?: false
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
        :lease_token,
        :lease_expires_at,
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
        :lease_token,
        :lease_expires_at,
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
      allow_nil? false
      attribute_public? true
    end

    belongs_to :organization_binding, OfficeGraph.AgentRuntime.OrganizationBinding do
      source_attribute :organization_binding_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :run, OfficeGraph.Runs.Run do
      source_attribute :run_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :graph_item_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :agent_principal, OfficeGraph.Identity.Principal do
      source_attribute :agent_principal_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :delegator_principal, OfficeGraph.Identity.Principal do
      source_attribute :delegator_principal_id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :proposed_changes, OfficeGraph.ProposedChanges.ProposedGraphChange do
      source_attribute :id
      destination_attribute :execution_id
    end

    has_many :authority_snapshots, OfficeGraph.AgentRuntime.AuthoritySnapshot do
      source_attribute :id
      destination_attribute :execution_id
    end

    has_many :context_packages, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :id
      destination_attribute :execution_id
    end

    has_many :model_requests, OfficeGraph.AgentRuntime.ModelRequest do
      source_attribute :id
      destination_attribute :execution_id
    end

    has_many :tool_requests, OfficeGraph.AgentRuntime.ToolRequest do
      source_attribute :id
      destination_attribute :execution_id
    end

    has_many :approval_requests, OfficeGraph.AgentRuntime.ApprovalRequest do
      source_attribute :id
      destination_attribute :execution_id
      public? true
    end

    has_many :context_expansion_requests, OfficeGraph.AgentRuntime.ContextExpansionRequest do
      source_attribute :id
      destination_attribute :execution_id
      public? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end
  end

  graphql do
    type :agent_execution

    paginate_relationship_with(
      approval_requests: :relay,
      context_expansion_requests: :relay
    )
  end

  json_api do
    type "agent_execution"
  end
end
