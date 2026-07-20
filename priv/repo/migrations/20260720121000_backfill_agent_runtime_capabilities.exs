defmodule OfficeGraph.Repo.Migrations.BackfillAgentRuntimeCapabilities do
  use Ecto.Migration

  @capability_keys ~w(agent.definition.bind agent.runtime.execute)

  def up do
    capability_values = Enum.map_join(@capability_keys, ",\n", &"('#{&1}')")

    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    SELECT
      md5('office_graph:capability:' || desired.key)::uuid,
      desired.key,
      desired.key,
      NOW(),
      NOW()
    FROM (VALUES
      #{capability_values}
    ) AS desired(key)
    ON CONFLICT (key) DO NOTHING
    """)

    execute("""
    INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
    SELECT
      md5(
        'office_graph:role_capability:' || roles.id::text || ':agent.definition.bind'
      )::uuid,
      roles.id,
      capabilities.id,
      NOW(),
      NOW()
    FROM roles
    JOIN capabilities ON capabilities.key = 'agent.definition.bind'
    WHERE roles.key = 'owner'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)
  end

  def down do
    # Conflict-safe capability backfills cannot distinguish authorization data
    # created here from data created before or after this migration.
    :ok
  end
end
