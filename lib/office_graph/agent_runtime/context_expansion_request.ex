defmodule OfficeGraph.AgentRuntime.ContextExpansionRequest do
  @moduledoc false

  @states ~w(pending approved denied cancelled expired superseded)

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_context_expansion_requests"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_pending_step:
                           "agent_context_expansion_requests_pending_step_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :execution_id, :uuid, allow_nil?: false, public?: true
    attribute :current_context_package_id, :uuid, allow_nil?: false, public?: true
    attribute :authority_snapshot_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :resolution_operation_id, :uuid, public?: true
    attribute :resolved_by_principal_id, :uuid, public?: true
    attribute :step_key, :string, allow_nil?: false, public?: true
    attribute :target_resource_type, :string, allow_nil?: false, public?: true
    attribute :target_resource_id, :uuid, allow_nil?: false, public?: true
    attribute :target_scope_type, :string, allow_nil?: false, public?: true
    attribute :target_scope_id, :uuid, allow_nil?: false, public?: true
    attribute :access_mode, :string, allow_nil?: false, public?: true
    attribute :capability_key, :string, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true
    attribute :sensitivity, :string, allow_nil?: false, public?: true
    attribute :expected_duration_seconds, :integer, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, default: 1, public?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :resolution_reason, :string, public?: true
    attribute :resolved_at, :utc_datetime_usec, public?: true
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
        :execution_id,
        :current_context_package_id,
        :authority_snapshot_id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :step_key,
        :target_resource_type,
        :target_resource_id,
        :target_scope_type,
        :target_scope_id,
        :access_mode,
        :capability_key,
        :reason,
        :sensitivity,
        :expected_duration_seconds,
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
  end

  identities do
    identity :unique_pending_step, [:execution_id, :step_key], where: expr(state == "pending")
  end

  relationships do
    belongs_to :execution, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :execution_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :current_context_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :current_context_package_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :authority_snapshot, OfficeGraph.AgentRuntime.AuthoritySnapshot do
      source_attribute :authority_snapshot_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
    end

    belongs_to :resolution_operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :resolution_operation_id
      define_attribute? false
    end

    belongs_to :resolved_by_principal, OfficeGraph.Identity.Principal do
      source_attribute :resolved_by_principal_id
      define_attribute? false
    end
  end
end
