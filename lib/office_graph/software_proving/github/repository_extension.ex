defmodule OfficeGraph.SoftwareProving.GitHub.RepositoryExtension do
  @moduledoc false

  use OfficeGraph.SoftwareProving.ProviderExtension,
    table: "github_repositories",
    accept: [:repository_id, :organization_id, :node_id, :database_id, :owner_login]

  attributes do
    attribute :repository_id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      writable?: true,
      public?: true

    attribute :organization_id, :uuid, allow_nil?: false, public?: true
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
      define_attribute? false
      public? true
    end
  end

  identities do
    identity :unique_organization_node_id, [:organization_id, :node_id]
  end
end
