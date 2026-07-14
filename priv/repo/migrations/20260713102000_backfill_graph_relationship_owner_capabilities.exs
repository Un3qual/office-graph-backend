defmodule OfficeGraph.Repo.Migrations.BackfillGraphRelationshipOwnerCapabilities do
  use Ecto.Migration

  @capability_keys ~w(
    graph_relationship.create
    graph_relationship.supersede
    graph_relationship.archive
    graph_relationship.restore
  )

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
        'office_graph:role_capability:' || roles.id::text || ':' || capabilities.key
      )::uuid,
      roles.id,
      capabilities.id,
      NOW(),
      NOW()
    FROM roles
    JOIN capabilities ON capabilities.key = ANY(ARRAY[#{quoted_capability_keys()}])
    WHERE roles.key = 'owner'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)
  end

  def down do
    # Conflict-safe backfills cannot distinguish grants created here from grants
    # created before or after this migration. Preserve authorization data.
    :ok
  end

  defp quoted_capability_keys do
    Enum.map_join(@capability_keys, ", ", &"'#{&1}'")
  end
end
