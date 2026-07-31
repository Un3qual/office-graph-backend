defmodule OfficeGraph.SoftwareProving.GitHub.ReviewThreadExtension do
  @moduledoc false

  use OfficeGraph.SoftwareProving.ProviderExtension,
    table: "github_review_threads",
    accept: [:review_thread_id, :organization_id, :workspace_id, :node_id]

  attributes do
    attribute :node_id, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :review_thread, OfficeGraph.SoftwareProving.ReviewThread do
      source_attribute :review_thread_id
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
    identity :unique_scope_node_id, [:organization_id, :workspace_id, :node_id],
      nils_distinct?: false
  end
end
