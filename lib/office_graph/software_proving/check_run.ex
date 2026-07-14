defmodule OfficeGraph.SoftwareProving.CheckRun do
  @moduledoc false

  use OfficeGraph.SoftwareProving.Resource,
    table: "check_runs",
    accept: [
      :repository_id,
      :commit_id,
      :pull_request_id,
      :name,
      :status,
      :conclusion,
      :details_url,
      :started_at,
      :completed_at
    ],
    validations: [
      status: ~w(queued in_progress completed),
      conclusion:
        ~w(success failure neutral cancelled skipped timed_out action_required startup_failure)
    ]

  attributes do
    attribute :repository_id, :uuid, allow_nil?: false, public?: true
    attribute :commit_id, :uuid, public?: true
    attribute :pull_request_id, :uuid, public?: true
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :status, :string, allow_nil?: false, public?: true

    attribute :conclusion, :string, public?: true

    attribute :details_url, :string, public?: true
    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :repository, OfficeGraph.SoftwareProving.Repository do
      source_attribute :repository_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :commit, OfficeGraph.SoftwareProving.Commit do
      source_attribute :commit_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    belongs_to :pull_request, OfficeGraph.SoftwareProving.PullRequest do
      source_attribute :pull_request_id
      destination_attribute :id
      define_attribute? false
      public? true
    end

    has_one :github_extension, OfficeGraph.SoftwareProving.GitHub.CheckRunExtension do
      destination_attribute :check_run_id
    end
  end
end
