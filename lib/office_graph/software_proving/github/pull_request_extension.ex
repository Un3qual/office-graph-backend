defmodule OfficeGraph.SoftwareProving.GitHub.PullRequestExtension do
  @moduledoc false

  use OfficeGraph.SoftwareProving.ProviderExtension,
    table: "github_pull_requests",
    accept: [:pull_request_id, :organization_id, :workspace_id, :node_id, :database_id]

  attributes do
    attribute :pull_request_id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      writable?: true,
      public?: true

    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :node_id, :string, allow_nil?: false, public?: true
    attribute :database_id, :integer, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :pull_request, OfficeGraph.SoftwareProving.PullRequest do
      source_attribute :pull_request_id
      destination_attribute :id
      define_attribute? false
      public? true
    end
  end

  identities do
    identity :unique_workspace_node_id, [:organization_id, :workspace_id, :node_id],
      where: expr(not is_nil(workspace_id))

    identity :unique_organization_node_id, [:organization_id, :node_id],
      where: expr(is_nil(workspace_id))
  end
end
