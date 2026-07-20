defmodule OfficeGraph.SoftwareProving.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.SoftwareProving.Repository
    resource OfficeGraph.SoftwareProving.RepositoryRef
    resource OfficeGraph.SoftwareProving.Commit
    resource OfficeGraph.SoftwareProving.PullRequest
    resource OfficeGraph.SoftwareProving.ReviewThread
    resource OfficeGraph.SoftwareProving.ReviewComment
    resource OfficeGraph.SoftwareProving.CheckRun
    resource OfficeGraph.SoftwareProving.GitHub.RepositoryExtension
    resource OfficeGraph.SoftwareProving.GitHub.PullRequestExtension
    resource OfficeGraph.SoftwareProving.GitHub.ReviewThreadExtension
    resource OfficeGraph.SoftwareProving.GitHub.ReviewCommentExtension
    resource OfficeGraph.SoftwareProving.GitHub.CheckRunExtension
  end
end
