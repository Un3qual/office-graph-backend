defmodule OfficeGraph.GitHubIntegration.InstallationCredential do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "github_installation_credentials"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_installation_purpose:
                           "github_installation_credentials_installation_purpose_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :installation_id, :uuid, allow_nil?: false, public?: true
    attribute :credential_id, :uuid, allow_nil?: false, public?: true
    attribute :purpose, :string, allow_nil?: false, public?: true
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
      accept [:id, :installation_id, :credential_id, :purpose, :operation_id]
      validate one_of(:purpose, ~w(webhook_secret app_private_key))
      public? false
    end
  end

  identities do
    identity :unique_installation_purpose, [:installation_id, :purpose]
  end

  relationships do
    belongs_to :installation, OfficeGraph.GitHubIntegration.Installation do
      source_attribute :installation_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :credential, OfficeGraph.Integrations.IntegrationCredential do
      source_attribute :credential_id
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
