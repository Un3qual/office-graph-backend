defmodule OfficeGraph.Repo.Migrations.ScopeGithubCheckRunsToPullRequests do
  use Ecto.Migration

  def up do
    alter table(:github_check_runs) do
      add :pull_request_id,
          references(:pull_requests, type: :binary_id, on_delete: :delete_all)
    end

    execute("""
    UPDATE github_check_runs AS extension
    SET pull_request_id = check_run.pull_request_id
    FROM check_runs AS check_run
    WHERE extension.check_run_id = check_run.id
    """)

    alter table(:github_check_runs) do
      modify :pull_request_id,
             references(:pull_requests, type: :binary_id, on_delete: :delete_all),
             null: false,
             from:
               {references(:pull_requests, type: :binary_id, on_delete: :delete_all), null: true}
    end

    drop_if_exists index(:github_check_runs, [], name: :github_check_runs_workspace_node_id_index)

    drop_if_exists index(:github_check_runs, [],
                     name: :github_check_runs_organization_node_id_index
                   )

    create unique_index(
             :github_check_runs,
             [:organization_id, :workspace_id, :node_id, :pull_request_id],
             where: "workspace_id IS NOT NULL",
             name: :github_check_runs_workspace_node_id_index
           )

    create unique_index(
             :github_check_runs,
             [:organization_id, :node_id, :pull_request_id],
             where: "workspace_id IS NULL",
             name: :github_check_runs_organization_node_id_index
           )
  end

  def down do
    raise Ecto.MigrationError,
          "irreversible migration: one GitHub check run can diverge across pull requests"
  end
end
