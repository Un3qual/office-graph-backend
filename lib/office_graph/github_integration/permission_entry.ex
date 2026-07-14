defmodule OfficeGraph.GitHubIntegration.PermissionEntry do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "github_permission_entries"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_snapshot_name: "github_permission_entries_snapshot_name_index"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :permission_snapshot_id, :uuid, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :access_level, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :permission_snapshot_id, :name, :access_level]
      validate one_of(:access_level, ~w(none read write admin))
      public? false
    end
  end

  identities do
    identity :unique_snapshot_name, [:permission_snapshot_id, :name]
  end

  relationships do
    belongs_to :permission_snapshot, OfficeGraph.GitHubIntegration.PermissionSnapshot do
      source_attribute :permission_snapshot_id
      destination_attribute :id
      define_attribute? false
      public? true
    end
  end
end
