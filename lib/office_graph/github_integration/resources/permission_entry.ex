defmodule OfficeGraph.GitHubIntegration.PermissionEntry do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "github_permission_entries"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_snapshot_name: "github_permission_entries_snapshot_name_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :access_level, :string, allow_nil?: false, public?: true
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
      public? true
      attribute_public? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     permission_snapshot.installation.organization_id ==
                       ^actor(:organization_id) and
                       (is_nil(permission_snapshot.installation.workspace_id) or
                          permission_snapshot.installation.workspace_id ==
                            ^actor(:workspace_id))
                   )
    end
  end

  graphql do
    type :github_permission_entry
  end

  json_api do
    type "github_permission_entry"
  end
end
