defmodule OfficeGraph.Repo.Migrations.BackfillAgentRuntimeDelegationCapabilities do
  use Ecto.Migration

  @capability_keys ~w(
    agent.model.generate
    agent.tool.read
    evidence.suggest
    openspec.read
    proposal.create
    repository.read
  )

  def up do
    capability_values = Enum.map_join(@capability_keys, ",\n", &"('#{&1}')")
    capability_key_array = Enum.map_join(@capability_keys, ",\n", &"'#{&1}'")

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
    JOIN capabilities ON capabilities.key = ANY(ARRAY[
      #{capability_key_array}
    ]::text[])
    WHERE roles.key = 'owner'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)
  end

  def down do
    # Conflict-safe capability grants are retained because the migration cannot
    # distinguish them from matching authorization data created independently.
    :ok
  end
end
