defmodule OfficeGraph.Integrations.IntegrationCredential do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Integrations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "integration_credentials"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_workspace_reference:
                           "integration_credentials_workspace_reference_index",
                         unique_organization_reference:
                           "integration_credentials_organization_reference_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :kind, :string, allow_nil?: false, public?: true
    attribute :secret_reference, :string, allow_nil?: false, public?: false, sensitive?: true
    attribute :status, :string, allow_nil?: false, default: "active", public?: true
    attribute :rotated_at, :utc_datetime_usec, public?: true
    attribute :expires_at, :utc_datetime_usec, public?: true
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
        :kind,
        :secret_reference,
        :status,
        :rotated_at,
        :expires_at,
        :operation_id
      ]

      validate one_of(:kind, ["secret_reference"])
      validate one_of(:status, ~w(active rotating revoked expired))
      public? false
    end

    update :set_status do
      accept [:status, :rotated_at, :expires_at]
      validate one_of(:status, ~w(active rotating revoked expired))
      require_atomic? false
      public? false
    end
  end

  identities do
    identity :unique_workspace_reference,
             [:organization_id, :workspace_id, :kind, :secret_reference],
             where: expr(not is_nil(workspace_id))

    identity :unique_organization_reference,
             [:organization_id, :kind, :secret_reference],
             where: expr(is_nil(workspace_id))
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

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      define_attribute? false
      public? true
    end
  end
end
