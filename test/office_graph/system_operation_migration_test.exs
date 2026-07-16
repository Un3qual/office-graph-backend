defmodule OfficeGraph.SystemOperationMigrationTest do
  use OfficeGraph.DataCase, async: false

  import OfficeGraph.TestSupport.PostgresCatalog

  test "system operation migration keeps human rows strict and permits declared system nullability" do
    assert column_nullable?("operation_correlations", "session_id")
    assert column_nullable?("operation_correlations", "workspace_id")
    assert column_exists?("operation_correlations", "operation_kind")
    assert column_exists?("operation_correlations", "authority_basis")
    assert column_exists?("operation_correlations", "causation_key")
    assert column_exists?("operation_correlations", "idempotency_scope")
    assert column_exists?("operation_correlations", "credential_id")
    assert column_exists?("operation_correlations", "subject_kind")
    assert column_exists?("operation_correlations", "subject_id")
    assert column_exists?("operation_correlations", "subject_version")
    assert constraint_exists?("operation_correlations_kind_valid")
    assert constraint_exists?("operation_correlations_human_context_required")
    assert constraint_exists?("operation_correlations_system_context_required")
    assert constraint_exists?("operation_correlations_subject_complete")
    refute index_exists?("operation_correlations_system_idempotency_index")

    assert %{columns: columns, nulls_not_distinct?: true} =
             index_definition("operation_correlations_system_scoped_idempotency_index")

    assert columns == [
             "organization_id",
             "workspace_id",
             "principal_id",
             "action",
             "idempotency_scope",
             "idempotency_key"
           ]

    assert column_nullable?("domain_events", "workspace_id")
    assert column_nullable?("domain_events", "subject_kind")
    assert column_nullable?("domain_events", "subject_id")
    assert column_nullable?("domain_events", "subject_version")
    assert column_exists?("domain_events", "event_scope")
    assert constraint_exists?("domain_events_scope_valid")
    assert constraint_exists?("domain_events_workspace_context_required")
    assert constraint_exists?("domain_events_subject_complete")
  end

  test "workspace-scoped system idempotency migrates online and is irreversible" do
    migration = OfficeGraph.Repo.Migrations.ScopeSystemOperationIdempotency

    unless Code.ensure_loaded?(migration) do
      Code.require_file(
        "priv/repo/migrations/20260715143000_scope_system_operation_idempotency.exs"
      )
    end

    migration_config = Function.capture(migration, :__migration__, 0)
    down = Function.capture(migration, :down, 0)

    assert migration_config.()[:disable_ddl_transaction]
    assert migration_config.()[:disable_migration_lock]

    assert_raise Ecto.MigrationError, ~r/irreversible.*workspaces/i, fn ->
      down.()
    end
  end
end
