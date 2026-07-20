defmodule OfficeGraph.Repo.Migrations.AllowOrganizationScopedGitHubOutboundActions do
  use Ecto.Migration

  def change do
    alter table(:github_outbound_actions) do
      modify :workspace_id, :binary_id, null: true
    end
  end
end
