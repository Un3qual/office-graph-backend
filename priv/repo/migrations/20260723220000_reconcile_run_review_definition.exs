defmodule OfficeGraph.Repo.Migrations.ReconcileRunReviewDefinition do
  use Ecto.Migration

  @reconciliation_failure_code "agent_definition_reconciled"

  def up do
    execute("""
    UPDATE agent_definitions
    SET key = 'run-review',
        updated_at = NOW()
    WHERE key = 'openspec-review'
      AND NOT EXISTS (
        SELECT 1
        FROM agent_definitions
        WHERE key = 'run-review'
      )
    """)

    # Snapshots are immutable and revalidated against the current definition.
    # Retire only work whose captured authority the canonical contract removes.
    incompatible_execution_ids = incompatible_execution_ids_sql()

    execute("""
    UPDATE agent_model_requests
    SET state = 'cancelled',
        failure_code = '#{@reconciliation_failure_code}',
        completed_at = COALESCE(completed_at, NOW())
    WHERE state IN ('pending', 'running', 'retry_scheduled')
      AND execution_id IN (#{incompatible_execution_ids})
    """)

    execute("""
    UPDATE agent_tool_requests
    SET state = 'cancelled',
        failure_code = '#{@reconciliation_failure_code}',
        completed_at = COALESCE(completed_at, NOW())
    WHERE state IN ('pending', 'running', 'retry_scheduled')
      AND execution_id IN (#{incompatible_execution_ids})
    """)

    execute("""
    UPDATE agent_approval_requests
    SET state = 'cancelled',
        version = version + 1,
        resolution_reason = '#{@reconciliation_failure_code}',
        resolved_at = NOW(),
        updated_at = NOW()
    WHERE state = 'pending'
      AND execution_id IN (#{incompatible_execution_ids})
    """)

    execute("""
    UPDATE agent_context_expansion_requests
    SET state = 'cancelled',
        version = version + 1,
        resolution_reason = '#{@reconciliation_failure_code}',
        resolved_at = NOW(),
        updated_at = NOW()
    WHERE state = 'pending'
      AND execution_id IN (#{incompatible_execution_ids})
    """)

    execute("""
    UPDATE agent_executions
    SET state = 'cancelled',
        state_version = state_version + 1,
        failure_code = '#{@reconciliation_failure_code}',
        lease_token = NULL,
        lease_expires_at = NULL,
        cancelled_at = NOW(),
        updated_at = NOW()
    WHERE id IN (#{incompatible_execution_ids})
    """)

    execute("""
    UPDATE agent_definitions
    SET name = 'Run Review',
        description = 'Reviews authorized Office Graph run context and proposes bounded follow-up.',
        supported_modes = ARRAY['human', 'automatic']::text[],
        requested_capabilities = ARRAY[
          'agent.invoke',
          'agent.model.generate',
          'evidence.suggest',
          'proposal.create'
        ]::text[],
        model_adapter_key = 'deterministic',
        tool_allowlist = ARRAY[]::text[],
        default_autonomy_mode = 'human_supervised',
        allowed_output_kinds = ARRAY[
          'message',
          'finding',
          'proposal',
          'observation',
          'evidence_candidate'
        ]::text[],
        updated_at = NOW()
    WHERE key = 'run-review'
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
    FROM agent_organization_bindings AS bindings
    JOIN agent_definitions AS definitions
      ON definitions.id = bindings.definition_id
     AND definitions.key = 'run-review'
    JOIN role_assignments AS assignments
      ON assignments.principal_id = bindings.agent_principal_id
     AND assignments.organization_id = bindings.organization_id
     AND assignments.workspace_id = bindings.workspace_id
    JOIN roles
      ON roles.id = assignments.role_id
     AND roles.organization_id = bindings.organization_id
     AND roles.key =
       'system:' || bindings.agent_principal_id::text ||
       ':workspace:' || bindings.workspace_id::text
    JOIN capabilities
      ON capabilities.key = ANY(ARRAY[
        'agent.model.generate',
        'proposal.create',
        'evidence.suggest'
      ]::text[])
    WHERE bindings.lifecycle_state = 'active'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)
  end

  def down do
    # The canonical definition key and approved configuration are retained.
    :ok
  end

  defp incompatible_execution_ids_sql do
    """
    SELECT executions.id
    FROM agent_executions AS executions
    JOIN agent_definitions AS definitions
      ON definitions.id = executions.definition_id
     AND definitions.key = 'run-review'
    JOIN agent_authority_snapshots AS snapshots
      ON snapshots.execution_id = executions.id
     AND snapshots.version = 1
    WHERE executions.state IN (
      'queued',
      'running',
      'waiting_approval',
      'waiting_context',
      'retry_scheduled'
    )
      AND (
        NOT (
          snapshots.capability_keys <@ ARRAY[
            'agent.invoke',
            'agent.model.generate',
            'evidence.suggest',
            'proposal.create'
          ]::text[]
        )
        OR cardinality(snapshots.tool_keys) > 0
      )
    """
  end
end
