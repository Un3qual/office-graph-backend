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
      assert column_exists?(table, "organization_id")
      assert column_exists?(table, "workspace_id")
      refute column_exists?(table, "lifecycle_state")

      assert index_columns("#{table}_workspace_node_id_index") == [
               "organization_id",
               "workspace_id",
               "node_id"
             ]

      assert index_columns("#{table}_organization_node_id_index") == [
               "organization_id",
               "node_id"
             ]

      assert %{unique?: true, predicate: workspace_predicate} =
               index_definition("#{table}_workspace_node_id_index")

      assert workspace_predicate =~ "workspace_id IS NOT NULL"

      assert %{unique?: true, predicate: organization_predicate} =
               index_definition("#{table}_organization_node_id_index")

      assert organization_predicate =~ "workspace_id IS NULL"
    end

    refute column_exists?("repositories", "github_node_id")
    refute column_exists?("pull_requests", "github_database_id")

    for column <-
          ~w(organization_id workspace_id provider object_type url sync_state operation_id) do
      assert column_exists?("external_references", column)
    end

    assert constraint_exists?("external_references_provider_scope_required")
    assert index_exists?("external_references_workspace_source_external_id_index")
    assert index_exists?("external_references_organization_source_external_id_index")
    assert index_exists?("integration_credentials_workspace_reference_index")
    assert index_exists?("integration_credentials_organization_reference_index")
  end

  test "scoping hardening is explicitly irreversible after scoped identities diverge" do
    migration = OfficeGraph.Repo.Migrations.HardenGitHubIntegrationScoping

    unless Code.ensure_loaded?(migration) do
      Code.require_file(
        "priv/repo/migrations/20260714110000_harden_github_integration_scoping.exs"
      )
    end

    down = Function.capture(migration, :down, 0)

    assert_raise Ecto.MigrationError, ~r/irreversible.*scoped identities/i, fn ->
      down.()
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

  defp index_columns(name) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT attribute.attname
        FROM pg_class index_relation
        JOIN pg_index index_definition ON index_definition.indexrelid = index_relation.oid
        JOIN pg_class table_relation ON table_relation.oid = index_definition.indrelid
        JOIN LATERAL unnest(index_definition.indkey) WITH ORDINALITY AS keys(attnum, position)
          ON true
        JOIN pg_attribute attribute
          ON attribute.attrelid = table_relation.oid AND attribute.attnum = keys.attnum
        WHERE index_relation.relname = $1
        ORDER BY keys.position
        """,
        [name]
      )

    Enum.map(rows, fn [column] -> column end)
  end

  defp index_definition(name) do
    %{rows: [[unique?, predicate]]} =
      Repo.query!(
        """
        SELECT index_definition.indisunique,
               pg_get_expr(index_definition.indpred, index_definition.indrelid)
        FROM pg_class index_relation
        JOIN pg_index index_definition ON index_definition.indexrelid = index_relation.oid
        WHERE index_relation.relname = $1
        """,
        [name]
      )

    %{unique?: unique?, predicate: predicate}
  end
end
