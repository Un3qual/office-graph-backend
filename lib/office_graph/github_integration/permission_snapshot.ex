defmodule OfficeGraph.GitHubIntegration.PermissionSnapshot do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "github_permission_snapshots"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_installation_version:
                           "github_permission_snapshots_installation_version_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :installation_id, :uuid, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, public?: true
    attribute :captured_at, :utc_datetime_usec, allow_nil?: false, public?: true
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
      accept [:id, :installation_id, :version, :captured_at, :operation_id]
      public? false
    end
  end

  identities do
    identity :unique_installation_version, [:installation_id, :version]
  end

  relationships do
    belongs_to :installation, OfficeGraph.GitHubIntegration.Installation do
      source_attribute :installation_id
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

    has_many :entries, OfficeGraph.GitHubIntegration.PermissionEntry do
      destination_attribute :permission_snapshot_id
    end
  end
end
