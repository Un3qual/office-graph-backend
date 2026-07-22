defmodule OfficeGraph.Repo.Migrations.BackfillAgentRuntimeGovernance do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    VALUES (
      md5('office_graph:capability:agent.invoke')::uuid,
      'agent.invoke',
      'agent.invoke',
      NOW(),
      NOW()
    )
    ON CONFLICT (key) DO NOTHING
    """)

    execute("""
    INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
    SELECT
      md5('office_graph:role_capability:' || roles.id::text || ':agent.invoke')::uuid,
      roles.id,
      capabilities.id,
      NOW(),
      NOW()
    FROM roles
    JOIN capabilities ON capabilities.key = 'agent.invoke'
    WHERE roles.key = 'owner'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)

    execute("""
    UPDATE agent_definitions
    SET allowed_output_kinds = ARRAY[
          'evidence_candidate',
          'finding',
          'message',
          'observation',
          'proposal'
        ]::text[],
        updated_at = NOW()
    WHERE key = 'openspec-review'
    """)
  end

  def down do
    # Conflict-safe authorization and approved definition backfills are retained.
    :ok
  end
end
