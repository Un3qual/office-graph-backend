defmodule OfficeGraph.SoftwareProving.PullRequest do
  @moduledoc false

  use OfficeGraph.SoftwareProving.Resource,
    table: "pull_requests",
    accept: [
      :repository_id,
      :number,
      :title,
      :body,
      :state,
      :is_draft,
      :base_ref_id,
      :head_ref_id,
      :author_label,
      :opened_at,
      :closed_at,
      :merged_at
    ],
    validations: [state: ~w(open closed merged)]

  attributes do
    attribute :repository_id, :uuid, allow_nil?: false, public?: true
    attribute :number, :integer, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :body, :string, public?: true

    attribute :state, :string, allow_nil?: false, public?: true

    attribute :is_draft, :boolean, allow_nil?: false, default: false, public?: true
    attribute :base_ref_id, :uuid, public?: true
    attribute :head_ref_id, :uuid, public?: true
    attribute :author_label, :string, public?: true
    attribute :opened_at, :utc_datetime_usec, public?: true
    attribute :closed_at, :utc_datetime_usec, public?: true
    attribute :merged_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :repository, OfficeGraph.SoftwareProving.Repository do
      source_attribute :repository_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :base_ref, OfficeGraph.SoftwareProving.RepositoryRef do
      source_attribute :base_ref_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :head_ref, OfficeGraph.SoftwareProving.RepositoryRef do
      source_attribute :head_ref_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    has_many :review_threads, OfficeGraph.SoftwareProving.ReviewThread
    has_many :review_comments, OfficeGraph.SoftwareProving.ReviewComment
    has_many :check_runs, OfficeGraph.SoftwareProving.CheckRun

    has_one :github_extension, OfficeGraph.SoftwareProving.GitHub.PullRequestExtension do
      destination_attribute :pull_request_id
    end
  end

  identities do
    identity :unique_repository_number, [:repository_id, :number]
  end
end
