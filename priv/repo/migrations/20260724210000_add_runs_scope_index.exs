defmodule OfficeGraph.Repo.Migrations.AddRunsScopeIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS runs_scope_inserted_at_id_index
    ON runs (organization_id, workspace_id, inserted_at DESC, id DESC)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS runs_scope_inserted_at_id_index")
  end
end
