defmodule OfficeGraph.GitHubIntegration.Installation do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "github_installations"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_external_installation:
                           "github_installations_external_installation_id_index",
                         unique_operation: "github_installations_operation_id_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :external_installation_id, :integer, allow_nil?: false, public?: true
    attribute :app_slug, :string, allow_nil?: false, public?: true
    attribute :account_login, :string, allow_nil?: false, public?: true
    attribute :account_type, :string, allow_nil?: false, public?: true
    attribute :service_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :webhook_principal_id, :uuid, allow_nil?: false, public?: true
    attribute :current_permission_snapshot_id, :uuid, public?: true

    attribute :lifecycle_state, :string,
      allow_nil?: false,
      default: "active",
      public?: true

    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :external_installation_id,
        :app_slug,
        :account_login,
        :account_type,
        :service_principal_id,
        :webhook_principal_id,
        :lifecycle_state,
        :operation_id
      ]

      validate one_of(:account_type, ~w(organization user))
      validate one_of(:lifecycle_state, ~w(active suspended revoked))
      public? false
    end

    update :set_permission_snapshot do
      accept [:current_permission_snapshot_id]
      require_atomic? false
      public? false
    end

    update :set_lifecycle do
      accept [:lifecycle_state]
      validate one_of(:lifecycle_state, ~w(active suspended revoked))
      require_atomic? false
      public? false
    end
  end

  identities do
    identity :unique_external_installation, [:external_installation_id]
    identity :unique_operation, [:operation_id]
  end

  relationships do
    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :governing_workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :service_principal, OfficeGraph.Identity.Principal do
      source_attribute :service_principal_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :webhook_principal, OfficeGraph.Identity.Principal do
      source_attribute :webhook_principal_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :current_permission_snapshot, OfficeGraph.GitHubIntegration.PermissionSnapshot do
      source_attribute :current_permission_snapshot_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    has_many :permission_snapshots, OfficeGraph.GitHubIntegration.PermissionSnapshot
    has_many :credential_bindings, OfficeGraph.GitHubIntegration.InstallationCredential
    has_many :sync_outcomes, OfficeGraph.GitHubIntegration.SyncOutcome
    has_many :outbound_actions, OfficeGraph.GitHubIntegration.OutboundAction
  end
end
