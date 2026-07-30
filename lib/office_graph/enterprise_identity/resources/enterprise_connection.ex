defmodule OfficeGraph.EnterpriseIdentity.EnterpriseConnection do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "enterprise_identity_connections"
    repo OfficeGraph.Repo

    identity_index_names provider_organization:
                           "enterprise_identity_connections_provider_organization_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :provider_organization_id, :string, allow_nil?: false, public?: true
    attribute :directory_requirement, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      attribute_public? true
    end

    belongs_to :webhook_principal, OfficeGraph.Identity.Principal do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      allow_nil? false
      attribute_public? true
    end

    has_many :directories, OfficeGraph.EnterpriseIdentity.Directory do
      destination_attribute :connection_id
    end

    has_many :sync_events, OfficeGraph.EnterpriseIdentity.DirectorySyncEvent do
      destination_attribute :connection_id
    end
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
        :organization_id,
        :workspace_id,
        :webhook_principal_id,
        :operation_id,
        :provider,
        :provider_organization_id,
        :directory_requirement,
        :status
      ]

      validate one_of(:provider, ["workos"])
      validate one_of(:directory_requirement, ~w(optional required))
      validate one_of(:status, ~w(active disabled))
    end

    update :set_lifecycle do
      public? false
      accept [:operation_id, :directory_requirement, :status]

      validate one_of(:directory_requirement, ~w(optional required)),
        where: [changing(:directory_requirement)]

      validate one_of(:status, ~w(active disabled)),
        where: [changing(:status)]

      require_atomic? false
    end
  end

  identities do
    identity :provider_organization, [:provider, :provider_organization_id]
  end
end
