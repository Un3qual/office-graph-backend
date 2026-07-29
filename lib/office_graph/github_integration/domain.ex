defmodule OfficeGraph.GitHubIntegration.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.GitHubIntegration.Installation, :get_github_installation, :read

      list OfficeGraph.GitHubIntegration.Installation, :list_github_installations, :read,
        relay?: true

      get OfficeGraph.GitHubIntegration.PermissionSnapshot,
          :get_github_permission_snapshot,
          :read

      list OfficeGraph.GitHubIntegration.PermissionSnapshot,
           :list_github_permission_snapshots,
           :read,
           relay?: true

      get OfficeGraph.GitHubIntegration.PermissionEntry,
          :get_github_permission_entry,
          :read

      list OfficeGraph.GitHubIntegration.PermissionEntry,
           :list_github_permission_entries,
           :read,
           relay?: true

      get OfficeGraph.GitHubIntegration.OutboundAction,
          :get_github_outbound_action,
          :read

      list OfficeGraph.GitHubIntegration.OutboundAction,
           :list_github_outbound_actions,
           :read,
           relay?: true
    end

    mutations do
      action OfficeGraph.GitHubIntegration.Installation,
             :bind_github_installation,
             :bind_github_installation

      action OfficeGraph.GitHubIntegration.OutboundAction,
             :reply_to_github_review,
             :reply_to_github_review do
        relay_id_translations(input: [installation_id: :github_installation])
      end

      action OfficeGraph.GitHubIntegration.OutboundAction,
             :update_github_check,
             :update_github_check do
        relay_id_translations(input: [installation_id: :github_installation])
      end
    end
  end

  json_api do
    routes do
      base_route "/github/installations", OfficeGraph.GitHubIntegration.Installation do
        get(:read, primary?: true)
        index :read
        related(:current_permission_snapshot, :read)
        related(:permission_snapshots, :read)
        related(:outbound_actions, :read)
      end

      base_route "/github/permission-snapshots",
                 OfficeGraph.GitHubIntegration.PermissionSnapshot do
        get(:read, primary?: true)
        index :read
        related(:installation, :read)
        related(:entries, :read)
      end

      base_route "/github/permission-entries",
                 OfficeGraph.GitHubIntegration.PermissionEntry do
        get(:read, primary?: true)
        index :read
        related(:permission_snapshot, :read)
      end

      base_route "/github/outbound-actions",
                 OfficeGraph.GitHubIntegration.OutboundAction do
        get(:read, primary?: true)
        index :read
        related(:installation, :read)
      end

      route(
        OfficeGraph.GitHubIntegration.Installation,
        :post,
        "/commands/bind-github-installation",
        :bind_github_installation
      )

      route(
        OfficeGraph.GitHubIntegration.OutboundAction,
        :post,
        "/commands/reply-to-github-review",
        :reply_to_github_review
      )

      route(
        OfficeGraph.GitHubIntegration.OutboundAction,
        :post,
        "/commands/update-github-check",
        :update_github_check
      )
    end
  end

  resources do
    resource OfficeGraph.GitHubIntegration.Installation
    resource OfficeGraph.GitHubIntegration.PermissionSnapshot
    resource OfficeGraph.GitHubIntegration.PermissionEntry
    resource OfficeGraph.GitHubIntegration.InstallationCredential
    resource OfficeGraph.GitHubIntegration.SyncOutcome
    resource OfficeGraph.GitHubIntegration.OutboundAction
  end
end
