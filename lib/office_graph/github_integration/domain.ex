defmodule OfficeGraph.GitHubIntegration.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.GitHubIntegration.Installation
    resource OfficeGraph.GitHubIntegration.PermissionSnapshot
    resource OfficeGraph.GitHubIntegration.PermissionEntry
    resource OfficeGraph.GitHubIntegration.InstallationCredential
    resource OfficeGraph.GitHubIntegration.SyncOutcome
  end
end
