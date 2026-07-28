defmodule OfficeGraph.SoftwareProving.GitHub.RepositoryExtension do
  @moduledoc false

  use OfficeGraph.SoftwareProving.ProviderExtension,
    table: "github_repositories",
    accept: [
      :repository_id,
      :organization_id,
      :workspace_id,
      :node_id,
      :database_id,
      :owner_login
    ]

  attributes do
    attribute :node_id, :string, allow_nil?: false, public?: true
    attribute :database_id, :integer, public?: true
    attribute :owner_login, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :repository, OfficeGraph.SoftwareProving.Repository do
      source_attribute :repository_id
      destination_attribute :id
      public? true
      attribute_public? true
      allow_nil? false
      primary_key? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      attribute_public? true
    end
  end

  identities do
    identity :unique_workspace_node_id, [:organization_id, :workspace_id, :node_id],
      where: expr(not is_nil(workspace_id))

    identity :unique_organization_node_id, [:organization_id, :node_id],
      where: expr(is_nil(workspace_id))
  end
end
