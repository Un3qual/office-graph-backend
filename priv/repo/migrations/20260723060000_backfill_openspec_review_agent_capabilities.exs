defmodule OfficeGraph.Repo.Migrations.BackfillOpenSpecReviewAgentCapabilities do
  use Ecto.Migration

  @capability_keys ~w(
    agent.invoke
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
    INSERT INTO role_capabilities (
      id,
      role_id,
      capability_id,
      inserted_at,
      updated_at
    )
    SELECT
      md5(
        'office_graph:role_capability:' ||
        assigned_roles.role_id::text ||
        ':' ||
        capabilities.key
      )::uuid,
      assigned_roles.role_id,
      capabilities.id,
      NOW(),
      NOW()
    FROM (
      SELECT DISTINCT role_assignments.role_id
      FROM agent_organization_bindings
      JOIN agent_definitions
        ON agent_definitions.id = agent_organization_bindings.definition_id
      JOIN role_assignments
        ON role_assignments.principal_id = agent_organization_bindings.agent_principal_id
       AND role_assignments.organization_id = agent_organization_bindings.organization_id
       AND role_assignments.workspace_id IS NOT DISTINCT FROM
           agent_organization_bindings.workspace_id
      WHERE agent_definitions.key = 'openspec-review'
    ) AS assigned_roles
    JOIN capabilities
      ON capabilities.key = ANY(ARRAY[
        #{capability_key_array}
      ]::text[])
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)
  end

  def down do
    # These grants are indistinguishable from equivalent authorization facts
    # created by a later binding replay, so rollback retains them.
    :ok
  end
end
