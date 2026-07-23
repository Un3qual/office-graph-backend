defmodule OfficeGraph.Repo.Migrations.AddNodeConversationCommands do
  use Ecto.Migration

  @capability_key "conversation.write"

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

    execute("""
    INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
    SELECT
      md5('office_graph:role_capability:' || roles.id::text || ':#{@capability_key}')::uuid,
      roles.id,
      capabilities.id,
      NOW(),
      NOW()
    FROM roles
    JOIN capabilities ON capabilities.key = '#{@capability_key}'
    WHERE roles.key = 'owner'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)
  end

  def down do
    execute("""
    DELETE FROM role_capabilities
    WHERE capability_id IN (
      SELECT id FROM capabilities WHERE key = '#{@capability_key}'
    )
    """)

    execute("DELETE FROM capabilities WHERE key = '#{@capability_key}'")
  end
end
