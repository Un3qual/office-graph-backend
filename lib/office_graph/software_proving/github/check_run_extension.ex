defmodule OfficeGraph.SoftwareProving.GitHub.CheckRunExtension do
  @moduledoc false

  use OfficeGraph.SoftwareProving.ProviderExtension,
    table: "github_check_runs",
    accept: [
      :check_run_id,
      :pull_request_id,
      :organization_id,
      :workspace_id,
      :node_id,
      :database_id,
      :check_suite_database_id
    ]

  attributes do
    attribute :node_id, :string, allow_nil?: false, public?: true
    attribute :database_id, :integer, public?: true
    attribute :check_suite_database_id, :integer, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :check_run, OfficeGraph.SoftwareProving.CheckRun do
      source_attribute :check_run_id
      destination_attribute :id
      public? true
      attribute_public? true
      allow_nil? false
      primary_key? true
    end

    belongs_to :pull_request, OfficeGraph.SoftwareProving.PullRequest do
      source_attribute :pull_request_id
      destination_attribute :id
      public? true
      attribute_public? true
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
    identity :unique_scope_node_id,
             [:organization_id, :workspace_id, :node_id, :pull_request_id],
             nils_distinct?: false
  end
end
