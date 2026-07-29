defmodule OfficeGraph.AgentRuntime.BindingResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :operation, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Operations.OperationCorrelation]

    field :definition, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.AgentRuntime.AgentDefinition]

    field :binding, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.AgentRuntime.OrganizationBinding]

    field :principal, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Identity.Principal]
  end

  def build!(operation, definition, binding, principal) do
    new!(
      operation: operation,
      definition: definition,
      binding: binding,
      principal: principal
    )
  end
end

defmodule OfficeGraph.AgentRuntime.OrganizationBinding do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_organization_bindings"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_definition_organization_workspace:
                           "agent_org_bindings_definition_org_workspace_index",
                         unique_organization_workspace_principal:
                           "agent_org_bindings_org_workspace_principal_index",
                         unique_operation: "agent_organization_bindings_operation_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    attribute :disabled_at, :utc_datetime_usec, public?: true
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
        :organization_id,
        :workspace_id,
        :agent_principal_id,
        :bound_by_principal_id,
        :lifecycle_state,
        :operation_id
      ]

      validate one_of(:lifecycle_state, ~w(active disabled revoked))
      change OfficeGraph.AgentRuntime.Changes.SyncBindingDisabledAt
    end

    action :persist_run_review_binding_contract, OfficeGraph.AgentRuntime.BindingResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.AgentRuntime.AgentDefinition,
        OfficeGraph.Authorization.Capability,
        OfficeGraph.Authorization.Role,
        OfficeGraph.Authorization.RoleAssignment,
        OfficeGraph.Authorization.RoleCapability,
        OfficeGraph.Identity.Principal,
        OfficeGraph.Operations.OperationCorrelation
      ]

      argument :operation_id, :uuid, allow_nil?: false

      run {OfficeGraph.AgentRuntime, mode: :bind_run_review}
    end

    update :set_lifecycle_state do
      public? false
      require_atomic? false
      accept [:lifecycle_state]
      validate one_of(:lifecycle_state, ~w(active disabled revoked))
      change OfficeGraph.AgentRuntime.Changes.SyncBindingDisabledAt
    end
  end

  identities do
    identity :unique_definition_organization_workspace, [
      :definition_id,
      :organization_id,
      :workspace_id
    ]

    identity :unique_organization_workspace_principal, [
      :organization_id,
      :workspace_id,
      :agent_principal_id
    ]

    identity :unique_operation, [:operation_id]
  end

  relationships do
    belongs_to :definition, OfficeGraph.AgentRuntime.AgentDefinition do
      source_attribute :definition_id
      allow_nil? false
      public? true
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      allow_nil? false
      public? true
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
      attribute_public? true
    end

    belongs_to :agent_principal, OfficeGraph.Identity.Principal do
      source_attribute :agent_principal_id
      allow_nil? false
      public? true
      attribute_public? true
    end

    belongs_to :bound_by_principal, OfficeGraph.Identity.Principal do
      source_attribute :bound_by_principal_id
      allow_nil? false
      public? true
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      public? true
      attribute_public? true
    end

    has_many :executions, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :id
      destination_attribute :organization_binding_id
    end
  end
end
