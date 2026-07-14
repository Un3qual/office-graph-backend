defmodule OfficeGraph.SoftwareProving.ReviewComment do
  @moduledoc false

  use OfficeGraph.SoftwareProving.Resource,
    table: "review_comments",
    accept: [
      :pull_request_id,
      :review_thread_id,
      :parent_comment_id,
      :body,
      :author_label,
      :state,
      :published_at
    ],
    validations: [state: ~w(pending published minimized deleted)]

  attributes do
    attribute :pull_request_id, :uuid, allow_nil?: false, public?: true
    attribute :review_thread_id, :uuid, public?: true
    attribute :parent_comment_id, :uuid, public?: true

    attribute :body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [allow_empty?: true]

    attribute :author_label, :string, public?: true

    attribute :state, :string, allow_nil?: false, public?: true

    attribute :published_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :pull_request, OfficeGraph.SoftwareProving.PullRequest do
      source_attribute :pull_request_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :review_thread, OfficeGraph.SoftwareProving.ReviewThread do
      source_attribute :review_thread_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :parent_comment, OfficeGraph.SoftwareProving.ReviewComment do
      source_attribute :parent_comment_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    has_one :github_extension, OfficeGraph.SoftwareProving.GitHub.ReviewCommentExtension do
      destination_attribute :review_comment_id
    end
  end
end
