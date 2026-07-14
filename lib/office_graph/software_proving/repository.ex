defmodule OfficeGraph.SoftwareProving.Repository do
  @moduledoc false

  use OfficeGraph.SoftwareProving.Resource,
    table: "repositories",
    accept: [:name, :full_name, :default_ref_name, :visibility],
    validations: [visibility: ~w(public internal private)]

  attributes do
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :full_name, :string, allow_nil?: false, public?: true
    attribute :default_ref_name, :string, public?: true

    attribute :visibility, :string, allow_nil?: false, public?: true
  end

  relationships do
    has_many :refs, OfficeGraph.SoftwareProving.RepositoryRef
    has_many :commits, OfficeGraph.SoftwareProving.Commit
    has_many :pull_requests, OfficeGraph.SoftwareProving.PullRequest
    has_many :check_runs, OfficeGraph.SoftwareProving.CheckRun

    has_one :github_extension, OfficeGraph.SoftwareProving.GitHub.RepositoryExtension do
      destination_attribute :repository_id
    end
  end
end
