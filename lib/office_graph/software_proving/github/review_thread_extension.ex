defmodule OfficeGraph.SoftwareProving.GitHub.ReviewThreadExtension do
  @moduledoc false

  use OfficeGraph.SoftwareProving.ProviderExtension,
    table: "github_review_threads",
    accept: [:review_thread_id, :organization_id, :workspace_id, :node_id]

  attributes do
    attribute :review_thread_id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      writable?: true,
      public?: true

    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, public?: true
    attribute :node_id, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :review_thread, OfficeGraph.SoftwareProving.ReviewThread do
      source_attribute :review_thread_id
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
