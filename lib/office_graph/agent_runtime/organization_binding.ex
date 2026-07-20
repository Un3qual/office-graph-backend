defmodule OfficeGraph.AgentRuntime.OrganizationBinding do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.AgentRuntime.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_organization_bindings"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_definition_organization:
                           "agent_organization_bindings_definition_organization_index",
                         unique_organization_principal:
                           "agent_organization_bindings_organization_principal_index",
                         unique_operation: "agent_organization_bindings_operation_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :definition_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :agent_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :bound_by_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
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
        :operation_id,
        :disabled_at
      ]

      validate one_of(:lifecycle_state, ~w(active disabled revoked))
    end

    update :set_lifecycle_state do
      public? false
      accept [:lifecycle_state, :disabled_at]
      validate one_of(:lifecycle_state, ~w(active disabled revoked))
    end
  end

  identities do
    identity :unique_definition_organization, [:definition_id, :organization_id]
    identity :unique_organization_principal, [:organization_id, :agent_principal_id]
    identity :unique_operation, [:operation_id]
  end

  relationships do
    belongs_to :definition, OfficeGraph.AgentRuntime.AgentDefinition do
      source_attribute :definition_id
      define_attribute? false
      allow_nil? false
      public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      define_attribute? false
      allow_nil? false
      public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      define_attribute? false
      public? true
    end

    belongs_to :agent_principal, OfficeGraph.Identity.Principal do
      source_attribute :agent_principal_id
      define_attribute? false
      allow_nil? false
      public? true
    end

    belongs_to :bound_by_principal, OfficeGraph.Identity.Principal do
      source_attribute :bound_by_principal_id
      define_attribute? false
      allow_nil? false
      public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      define_attribute? false
      allow_nil? false
      public? true
    end
  end
end
