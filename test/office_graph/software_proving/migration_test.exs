defmodule OfficeGraph.SoftwareProving.MigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Repo

  @base_tables ~w(repositories repository_refs commits pull_requests review_threads review_comments check_runs)
  @github_extension_tables ~w(github_repositories github_pull_requests github_review_threads github_review_comments github_check_runs)

  test "software proving tables own typed scope, lifecycle, provider ordering, and extensions" do
    for table <- @base_tables do
      assert table_exists?(table)
      assert column_exists?(table, "organization_id")
      assert column_exists?(table, "workspace_id")
      assert column_exists?(table, "source_id")
      assert column_exists?(table, "provider_version")
      assert column_exists?(table, "provider_sequence")
      assert column_exists?(table, "provider_updated_at")
      assert column_exists?(table, "sync_state")
      assert column_exists?(table, "lifecycle_state")
      assert column_exists?(table, "operation_id")
      assert column_exists?(table, "deleted_at")
      assert constraint_exists?("#{table}_sync_state_valid")
      assert constraint_exists?("#{table}_lifecycle_state_valid")
      assert index_exists?("#{table}_scope_index")
    end

    for table <- @github_extension_tables do
      assert table_exists?(table)
      assert column_exists?(table, "node_id")
      refute column_exists?(table, "organization_id")
      refute column_exists?(table, "workspace_id")
      refute column_exists?(table, "lifecycle_state")
    end

    refute column_exists?("repositories", "github_node_id")
    refute column_exists?("pull_requests", "github_database_id")

    for column <- ~w(organization_id provider object_type url sync_state operation_id) do
      assert column_exists?("external_references", column)
    end
  end

  defp table_exists?(table) do
    %{rows: [[exists?]]} =
      Repo.query!(
        "SELECT to_regclass(current_schema() || '.' || $1) IS NOT NULL",
        [table]
      )

    exists?
  end

  defp column_exists?(table, column) do
    %{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema = current_schema()
            AND table_name = $1
            AND column_name = $2
        )
        """,
        [table, column]
      )

    exists?
  end

  defp constraint_exists?(name) do
    %{rows: [[exists?]]} =
      Repo.query!("SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = $1)", [name])

    exists?
  end

  defp index_exists?(name) do
    %{rows: [[exists?]]} =
      Repo.query!(
        "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = current_schema() AND indexname = $1)",
        [name]
      )

    exists?
  end
end
