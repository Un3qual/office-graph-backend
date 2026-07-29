defmodule OfficeGraph.AgentRuntime.ApprovalResolutionResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :request, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.AgentRuntime.ApprovalRequest]

    field :execution, :struct,
      allow_nil?: false,
      constraints: [
        instance_of: Module.concat([OfficeGraph, AgentRuntime, AgentExecution])
      ]
  end

  def build!(request, execution), do: new!(request: request, execution: execution)
end

defmodule OfficeGraph.AgentRuntime.ApprovalRequest do
  @moduledoc false

  @states ~w(pending approved denied cancelled expired superseded)

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "agent_approval_requests"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_pending_step: "agent_approval_requests_pending_step_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :step_key, :string, allow_nil?: false, public?: true

    attribute :execution_state_version, :integer,
      allow_nil?: false,
      constraints: [min: 1],
      public?: true

    attribute :requested_action, :string, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true
    attribute :scope_type, :string, allow_nil?: false, public?: true
    attribute :scope_id, :uuid, allow_nil?: false, public?: true
    attribute :capability_key, :string, public?: true
    attribute :sensitivity, :string, allow_nil?: false, public?: true
    attribute :external_write, :boolean, allow_nil?: false, default: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    attribute :version, :integer,
      allow_nil?: false,
      default: 1,
      constraints: [min: 1],
      public?: true

    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :resolution_reason, :string, public?: true
    attribute :resolved_at, :utc_datetime_usec, public?: true
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
        :execution_id,
        :authority_snapshot_id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :credential_id,
        :context_expansion_request_id,
        :step_key,
        :execution_state_version,
        :requested_action,
        :reason,
        :scope_type,
        :scope_id,
        :capability_key,
        :sensitivity,
        :external_write,
        :state,
        :version,
        :expires_at
      ]

      validate one_of(:state, @states)
    end

    update :resolve do
      public? false

      accept [
        :state,
        :version,
        :resolution_operation_id,
        :resolved_by_principal_id,
        :resolution_reason,
        :resolved_at
      ]

      validate one_of(:state, @states)
    end

    update :set_expiry do
      public? false
      accept [:expires_at]
    end

    action :persist_resolution_contract, OfficeGraph.AgentRuntime.ApprovalResolutionResult do
      public? false
      transaction? true

      touches_resources [
        Module.concat([OfficeGraph, AgentRuntime, AgentExecution]),
        OfficeGraph.AgentRuntime.ModelRequest,
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.DurableDelivery.DomainEvent,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :request_id, :uuid, allow_nil?: false
      argument :expected_version, :integer, allow_nil?: false, constraints: [min: 1]
      argument :decision, :string, allow_nil?: false

      argument :resolution_reason, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/, max_length: 2_000]

      validate argument_in(:decision, ~w(approved denied cancelled))

      run {Module.concat([OfficeGraph, AgentRuntime, ApprovalCommands]),
           mode: :persist_resolution}
    end

    action :expire_gate_contract,
           Module.concat([OfficeGraph, AgentRuntime, GateExpiryResult]) do
      public? false
      transaction? true

      touches_resources [
        Module.concat([OfficeGraph, AgentRuntime, AgentExecution]),
        OfficeGraph.DurableDelivery.DomainEvent,
        OfficeGraph.Operations.OperationCorrelation
      ]

      argument :request_id, :uuid, allow_nil?: false

      run {Module.concat([OfficeGraph, AgentRuntime, GateExpiryWorker]), request_kind: "approval"}
    end
  end

  identities do
    identity :unique_pending_step, [:execution_id, :step_key], where: expr(state == "pending")
  end

  relationships do
    belongs_to :execution, Module.concat([OfficeGraph, AgentRuntime, AgentExecution]) do
      source_attribute :execution_id
      allow_nil? false
      attribute_public? true
      public? true
    end

    belongs_to :authority_snapshot, OfficeGraph.AgentRuntime.AuthoritySnapshot do
      source_attribute :authority_snapshot_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :resolution_operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :resolution_operation_id
      attribute_public? true
    end

    belongs_to :resolved_by_principal, OfficeGraph.Identity.Principal do
      source_attribute :resolved_by_principal_id
      attribute_public? true
    end

    belongs_to :credential, OfficeGraph.Integrations.IntegrationCredential do
      source_attribute :credential_id
      attribute_public? true
    end

    belongs_to :context_expansion_request,
               Module.concat([OfficeGraph, AgentRuntime, ContextExpansionRequest]) do
      source_attribute :context_expansion_request_id
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
    type :agent_approval_request
  end

  json_api do
    type "agent_approval_request"
  end
end
