defmodule OfficeGraph.Repo.Migrations.CreateSoftwareProvingResources do
  use Ecto.Migration

  @base_tables ~w(repositories repository_refs commits pull_requests review_threads review_comments check_runs)a

  def up do
    create table(:repositories, primary_key: false) do
      common_columns()
      add :name, :text, null: false
      add :full_name, :text, null: false
      add :default_ref_name, :text
      add :visibility, :text, null: false
    end

    create table(:commits, primary_key: false) do
      common_columns()

      add :repository_id, references(:repositories, type: :binary_id, on_delete: :restrict),
        null: false

      add :oid, :text, null: false
      add :summary, :text
      add :authored_at, :utc_datetime_usec
      add :committed_at, :utc_datetime_usec
    end

    create table(:repository_refs, primary_key: false) do
      common_columns()

      add :repository_id, references(:repositories, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :text, null: false
      add :ref_type, :text, null: false
      add :target_commit_id, references(:commits, type: :binary_id, on_delete: :nilify_all)
      add :is_default, :boolean, null: false, default: false
    end

    create table(:pull_requests, primary_key: false) do
      common_columns()

      add :repository_id, references(:repositories, type: :binary_id, on_delete: :restrict),
        null: false

      add :number, :bigint, null: false
      add :title, :text, null: false
      add :body, :text
      add :state, :text, null: false
      add :is_draft, :boolean, null: false, default: false
      add :base_ref_id, references(:repository_refs, type: :binary_id, on_delete: :nilify_all)
      add :head_ref_id, references(:repository_refs, type: :binary_id, on_delete: :nilify_all)
      add :author_label, :text
      add :opened_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec
      add :merged_at, :utc_datetime_usec
    end

    create table(:review_threads, primary_key: false) do
      common_columns()

      add :pull_request_id, references(:pull_requests, type: :binary_id, on_delete: :restrict),
        null: false

      add :state, :text, null: false
      add :path, :text
      add :line, :integer
      add :side, :text
      add :resolved_at, :utc_datetime_usec
    end

    create table(:review_comments, primary_key: false) do
      common_columns()

      add :pull_request_id, references(:pull_requests, type: :binary_id, on_delete: :restrict),
        null: false

      add :review_thread_id, references(:review_threads, type: :binary_id, on_delete: :nilify_all)

      add :parent_comment_id,
          references(:review_comments, type: :binary_id, on_delete: :nilify_all)

      add :body, :text, null: false
      add :author_label, :text
      add :state, :text, null: false
      add :published_at, :utc_datetime_usec
    end

    create table(:check_runs, primary_key: false) do
      common_columns()

      add :repository_id, references(:repositories, type: :binary_id, on_delete: :restrict),
        null: false

      add :commit_id, references(:commits, type: :binary_id, on_delete: :nilify_all)
      add :pull_request_id, references(:pull_requests, type: :binary_id, on_delete: :nilify_all)
      add :name, :text, null: false
      add :status, :text, null: false
      add :conclusion, :text
      add :details_url, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
    end

    create unique_index(:repository_refs, [:repository_id, :name],
             name: :repository_refs_repository_name_index
           )

    create unique_index(:commits, [:repository_id, :oid], name: :commits_repository_oid_index)

    create unique_index(:pull_requests, [:repository_id, :number],
             name: :pull_requests_repository_number_index
           )

    create index(:review_threads, [:pull_request_id, :state],
             name: :review_threads_pull_request_state_index
           )

    create index(:review_comments, [:pull_request_id, :published_at],
             name: :review_comments_pull_request_published_index
           )

    create index(:check_runs, [:repository_id, :status, :provider_updated_at],
             name: :check_runs_repository_status_index
           )

    for table <- @base_tables do
      create index(table, [:organization_id, :workspace_id],
               name: String.to_atom("#{table}_scope_index")
             )

      create index(table, [:source_id, :provider_sequence],
               name: String.to_atom("#{table}_provider_sequence_index")
             )

      create constraint(table, String.to_atom("#{table}_sync_state_valid"),
               check: "sync_state IN ('native', 'pending', 'synced', 'stale', 'failed')"
             )

      create constraint(table, String.to_atom("#{table}_lifecycle_state_valid"),
               check: "lifecycle_state IN ('active', 'archived', 'deleted')"
             )

      create constraint(table, String.to_atom("#{table}_provider_sequence_positive"),
               check: "provider_sequence IS NULL OR provider_sequence >= 0"
             )
    end

    create table(:github_repositories, primary_key: false) do
      add :repository_id,
          references(:repositories, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :node_id, :text, null: false
      add :database_id, :bigint
      add :owner_login, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:github_pull_requests, primary_key: false) do
      add :pull_request_id,
          references(:pull_requests, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :node_id, :text, null: false
      add :database_id, :bigint
      timestamps(type: :utc_datetime_usec)
    end

    create table(:github_review_threads, primary_key: false) do
      add :review_thread_id,
          references(:review_threads, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :node_id, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:github_review_comments, primary_key: false) do
      add :review_comment_id,
          references(:review_comments, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :node_id, :text, null: false
      add :database_id, :bigint
      add :review_database_id, :bigint
      timestamps(type: :utc_datetime_usec)
    end

    create table(:github_check_runs, primary_key: false) do
      add :check_run_id,
          references(:check_runs, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :node_id, :text, null: false
      add :database_id, :bigint
      add :check_suite_database_id, :bigint
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_repositories, [:node_id])
    create unique_index(:github_pull_requests, [:node_id])
    create unique_index(:github_review_threads, [:node_id])
    create unique_index(:github_review_comments, [:node_id])
    create unique_index(:github_check_runs, [:node_id])

    alter table(:external_references) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict)
      add :provider, :text
      add :object_type, :text
      add :url, :text
      add :sync_state, :text, null: false, default: "synced"

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict)
    end

    create index(:external_references, [:organization_id, :provider, :object_type],
             name: :external_references_provider_scope_index
           )

    create constraint(:external_references, :external_references_sync_state_valid,
             check: "sync_state IN ('pending', 'synced', 'stale', 'failed')"
           )
  end

  def down do
    drop constraint(:external_references, :external_references_sync_state_valid)

    drop_if_exists index(:external_references, [],
                     name: :external_references_provider_scope_index
                   )

    alter table(:external_references) do
      remove :operation_id
      remove :sync_state
      remove :url
      remove :object_type
      remove :provider
      remove :organization_id
    end

    drop table(:github_check_runs)
    drop table(:github_review_comments)
    drop table(:github_review_threads)
    drop table(:github_pull_requests)
    drop table(:github_repositories)
    drop table(:check_runs)
    drop table(:review_comments)
    drop table(:review_threads)
    drop table(:pull_requests)
    drop table(:repository_refs)
    drop table(:commits)
    drop table(:repositories)
  end

  defp common_columns do
    add :id, :binary_id, primary_key: true

    add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
      null: false

    add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
    add :source_id, references(:external_sources, type: :binary_id, on_delete: :restrict)
    add :provider_version, :text
    add :provider_sequence, :bigint
    add :provider_updated_at, :utc_datetime_usec
    add :sync_state, :text, null: false, default: "native"
    add :lifecycle_state, :text, null: false, default: "active"

    add :operation_id,
        references(:operation_correlations, type: :binary_id, on_delete: :restrict),
        null: false

    add :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
