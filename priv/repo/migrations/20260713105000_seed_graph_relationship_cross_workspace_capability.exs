defmodule OfficeGraph.Repo.Migrations.SeedGraphRelationshipCrossWorkspaceCapability do
  use Ecto.Migration

  @capability_key "graph_relationship.cross_workspace"

  def up do
    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    VALUES (
      md5('office_graph:capability:#{@capability_key}')::uuid,
      '#{@capability_key}',
      '#{@capability_key}',
      NOW(),
      NOW()
    )
    ON CONFLICT (key) DO NOTHING
    """)
  end

  def down do
    # The capability can be referenced by grants created after this migration.
    # Preserve authorization data on rollback.
    :ok
  end
end
