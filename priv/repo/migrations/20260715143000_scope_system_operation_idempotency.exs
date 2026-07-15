defmodule OfficeGraph.Repo.Migrations.ScopeSystemOperationIdempotency do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create unique_index(
             :operation_correlations,
             [
               :organization_id,
               :workspace_id,
               :principal_id,
               :action,
               :idempotency_scope,
               :idempotency_key
             ],
             where: "operation_kind = 'system'",
             name: :operation_correlations_system_scoped_idempotency_index,
             nulls_distinct: false,
             concurrently: true
           )

    drop index(:operation_correlations, [],
           name: :operation_correlations_system_idempotency_index,
           concurrently: true
         )
  end

  def down do
    raise Ecto.MigrationError,
          "irreversible migration: separate workspaces can reuse system idempotency keys"
  end
end
