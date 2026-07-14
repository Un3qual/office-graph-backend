defmodule OfficeGraph.SystemOperationMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Repo

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
    assert index_exists?("operation_correlations_system_idempotency_index")

    assert column_nullable?("domain_events", "workspace_id")
    assert column_nullable?("domain_events", "subject_kind")
    assert column_nullable?("domain_events", "subject_id")
    assert column_nullable?("domain_events", "subject_version")
    assert column_exists?("domain_events", "event_scope")
    assert constraint_exists?("domain_events_scope_valid")
    assert constraint_exists?("domain_events_workspace_context_required")
    assert constraint_exists?("domain_events_subject_complete")
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

  defp column_nullable?(table, column) do
    %{rows: [["YES"]]} =
      Repo.query!(
        """
        SELECT is_nullable
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = $1
          AND column_name = $2
        """,
        [table, column]
      )

    true
  end

  defp constraint_exists?(name) do
    %{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = $1
        )
        """,
        [name]
      )

    exists?
  end

  defp index_exists?(name) do
    %{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_indexes
          WHERE schemaname = current_schema()
            AND indexname = $1
        )
        """,
        [name]
      )

    exists?
  end
end
