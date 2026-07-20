defmodule OfficeGraph.SoftwareProving.MigrationTest do
  use OfficeGraph.DataCase, async: false

  import OfficeGraph.TestSupport.PostgresCatalog

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

      workspace_identity_columns =
        if table == "github_check_runs",
          do: ["organization_id", "workspace_id", "node_id", "pull_request_id"],
          else: ["organization_id", "workspace_id", "node_id"]

      organization_identity_columns =
        if table == "github_check_runs",
          do: ["organization_id", "node_id", "pull_request_id"],
          else: ["organization_id", "node_id"]

      assert index_columns("#{table}_workspace_node_id_index") == workspace_identity_columns

      assert index_columns("#{table}_organization_node_id_index") ==
               organization_identity_columns

      assert %{unique?: true, predicate: workspace_predicate} =
               index_definition("#{table}_workspace_node_id_index")

      assert workspace_predicate =~ "workspace_id IS NOT NULL"

      assert %{unique?: true, predicate: organization_predicate} =
               index_definition("#{table}_organization_node_id_index")

      assert organization_predicate =~ "workspace_id IS NULL"
    end

    assert column_exists?("github_check_runs", "pull_request_id")
    refute column_nullable?("github_check_runs", "pull_request_id")

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
    assert column_nullable?("github_outbound_actions", "workspace_id")

    assert index_columns("external_sources_kind_key_index") == ["kind", "key"]
    refute index_exists?("external_sources_key_index")
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

  test "external source identity indexes migrate concurrently and remain irreversible" do
    migration = OfficeGraph.Repo.Migrations.ScopeExternalSourceIdentities

    unless Code.ensure_loaded?(migration) do
      Code.require_file(
        "priv/repo/migrations/20260714111000_scope_external_source_identities.exs"
      )
    end

    migration_config = Function.capture(migration, :__migration__, 0)
    down = Function.capture(migration, :down, 0)

    assert migration_config.()[:disable_ddl_transaction]
    assert migration_config.()[:disable_migration_lock]

    assert_raise Ecto.MigrationError, ~r/irreversible.*source kinds/i, fn ->
      down.()
    end
  end
end
