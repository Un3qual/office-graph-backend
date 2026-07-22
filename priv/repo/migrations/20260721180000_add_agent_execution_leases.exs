defmodule OfficeGraph.Repo.Migrations.AddAgentExecutionLeases do
  use Ecto.Migration

  def up do
    alter table(:agent_executions) do
      add :lease_token, :text
      add :lease_expires_at, :utc_datetime_usec
    end

    create index(:agent_executions, [:state, :lease_expires_at],
             name: :agent_executions_state_lease_index
           )

    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    VALUES (
      md5('office_graph:capability:agent.cancel')::uuid,
      'agent.cancel',
      'agent.cancel',
      NOW(),
      NOW()
    )
    ON CONFLICT (key) DO NOTHING
    """)

    execute("""
    INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
    SELECT
      md5('office_graph:role_capability:' || roles.id::text || ':agent.cancel')::uuid,
      roles.id,
      capabilities.id,
      NOW(),
      NOW()
    FROM roles
    JOIN capabilities ON capabilities.key = 'agent.cancel'
    WHERE roles.key = 'owner'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)

    execute("""
    UPDATE agent_definitions
    SET requested_capabilities = ARRAY(
          SELECT DISTINCT capability
          FROM unnest(
            requested_capabilities || ARRAY['agent.model.generate', 'agent.tool.read']::text[]
          ) AS capability
          ORDER BY capability
        ),
        updated_at = NOW()
    WHERE key = 'openspec-review'
    """)
  end

  def down do
    drop_if_exists index(:agent_executions, [:state, :lease_expires_at],
                     name: :agent_executions_state_lease_index
                   )

    alter table(:agent_executions) do
      remove :lease_expires_at
      remove :lease_token
    end
  end
end
