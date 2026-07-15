defmodule OfficeGraph.Repo.Migrations.HardenGitHubIntegrationScoping do
  use Ecto.Migration

  @github_extensions [
    {:github_repositories, :repositories, :repository_id},
    {:github_pull_requests, :pull_requests, :pull_request_id},
    {:github_review_threads, :review_threads, :review_thread_id},
    {:github_review_comments, :review_comments, :review_comment_id},
    {:github_check_runs, :check_runs, :check_run_id}
  ]

  def up do
    for {extension, base, base_id} <- @github_extensions do
      alter table(extension) do
        add :organization_id,
            references(:organizations, type: :binary_id, on_delete: :restrict)

        add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
      end

      execute("""
      UPDATE #{extension} AS extension
      SET organization_id = base.organization_id,
          workspace_id = base.workspace_id
      FROM #{base} AS base
      WHERE extension.#{base_id} = base.id
      """)

      alter table(extension) do
        modify :organization_id,
               references(:organizations, type: :binary_id, on_delete: :restrict),
               null: false,
               from:
                 {references(:organizations, type: :binary_id, on_delete: :restrict), null: true}
      end

      index_name = String.to_atom("#{extension}_node_id_index")
      drop_if_exists index(extension, [], name: index_name)

      create unique_index(extension, [:organization_id, :workspace_id, :node_id],
               where: "workspace_id IS NOT NULL",
               name: String.to_atom("#{extension}_workspace_node_id_index")
             )

      create unique_index(extension, [:organization_id, :node_id],
               where: "workspace_id IS NULL",
               name: String.to_atom("#{extension}_organization_node_id_index")
             )
    end

    alter table(:external_references) do
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
    end

    execute("""
    UPDATE external_references AS reference
    SET workspace_id = operation.workspace_id
    FROM operation_correlations AS operation
    WHERE reference.operation_id = operation.id
      AND reference.organization_id IS NOT NULL
    """)

    drop_if_exists index(:external_references, [],
                     name: :external_references_source_id_external_id_index
                   )

    create unique_index(
             :external_references,
             [:organization_id, :workspace_id, :source_id, :external_id],
             where: "workspace_id IS NOT NULL",
             name: :external_references_workspace_source_external_id_index
           )

    create unique_index(
             :external_references,
             [:organization_id, :source_id, :external_id],
             where: "organization_id IS NOT NULL AND workspace_id IS NULL",
             name: :external_references_organization_source_external_id_index
           )

    create unique_index(
             :external_references,
             [:source_id, :external_id],
             where: "organization_id IS NULL",
             name: :external_references_source_id_external_id_index
           )

    create constraint(:external_references, :external_references_provider_scope_required,
             check:
               "provider IS NULL OR (organization_id IS NOT NULL AND operation_id IS NOT NULL)"
           )

    drop_if_exists index(:integration_credentials, [],
                     name: :integration_credentials_scope_reference_index
                   )

    create unique_index(
             :integration_credentials,
             [:organization_id, :workspace_id, :kind, :secret_reference],
             where: "workspace_id IS NOT NULL",
             name: :integration_credentials_workspace_reference_index
           )

    create unique_index(
             :integration_credentials,
             [:organization_id, :kind, :secret_reference],
             where: "workspace_id IS NULL",
             name: :integration_credentials_organization_reference_index
           )
  end

  def down do
    raise Ecto.MigrationError,
          "irreversible migration: scoped identities can diverge after GitHub integration hardening"
  end
end
