defmodule OfficeGraph.SoftwareProving.GitHub.ReviewCommentExtension do
  @moduledoc false

  use OfficeGraph.SoftwareProving.ProviderExtension,
    table: "github_review_comments",
    accept: [:review_comment_id, :node_id, :database_id, :review_database_id]

  attributes do
    attribute :review_comment_id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      writable?: true,
      public?: true

    attribute :node_id, :string, allow_nil?: false, public?: true
    attribute :database_id, :integer, public?: true
    attribute :review_database_id, :integer, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :review_comment, OfficeGraph.SoftwareProving.ReviewComment do
      source_attribute :review_comment_id
      destination_attribute :id
      define_attribute? false
      public? true
    end
  end

  identities do
    identity :unique_node_id, [:node_id]
  end
end
