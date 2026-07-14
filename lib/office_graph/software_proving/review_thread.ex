defmodule OfficeGraph.SoftwareProving.ReviewThread do
  @moduledoc false

  use OfficeGraph.SoftwareProving.Resource,
    table: "review_threads",
    accept: [:pull_request_id, :state, :path, :line, :side, :resolved_at],
    validations: [state: ~w(open resolved outdated)]

  attributes do
    attribute :pull_request_id, :uuid, allow_nil?: false, public?: true

    attribute :state, :string, allow_nil?: false, public?: true

    attribute :path, :string, public?: true
    attribute :line, :integer, public?: true

    attribute :side, :string, public?: true

    attribute :resolved_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :pull_request, OfficeGraph.SoftwareProving.PullRequest do
      source_attribute :pull_request_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    has_many :comments, OfficeGraph.SoftwareProving.ReviewComment

    has_one :github_extension, OfficeGraph.SoftwareProving.GitHub.ReviewThreadExtension do
      destination_attribute :review_thread_id
    end
  end
end
