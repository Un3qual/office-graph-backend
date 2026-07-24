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
    # Materialize the target set before changing parent state so child cleanup
    # remains stable. Waiting gates keep their established child-before-parent
    # order; active model work keeps execution-before-request order.
    execute("DROP TABLE IF EXISTS pg_temp.reconcile_run_review_incompatible_executions")

    execute("""
    CREATE TEMP TABLE reconcile_run_review_incompatible_executions (
      id uuid PRIMARY KEY,
      state text NOT NULL
    ) ON COMMIT DROP
    """)

    execute("""
    INSERT INTO pg_temp.reconcile_run_review_incompatible_executions (id, state)
    #{incompatible_executions_sql()}
    """)

    execute("""
    UPDATE agent_approval_requests
    SET state = 'cancelled',
        version = version + 1,
        resolution_reason = '#{@reconciliation_failure_code}',
        resolved_at = NOW(),
        updated_at = NOW()
    WHERE state = 'pending'
      AND execution_id IN (
        SELECT id
        FROM pg_temp.reconcile_run_review_incompatible_executions
        WHERE state = 'waiting_approval'
      )
    """)

    execute("""
    UPDATE agent_context_expansion_requests
    SET state = 'cancelled',
        version = version + 1,
        resolution_reason = '#{@reconciliation_failure_code}',
        resolved_at = NOW(),
        updated_at = NOW()
    WHERE state = 'pending'
      AND execution_id IN (
        SELECT id
        FROM pg_temp.reconcile_run_review_incompatible_executions
        WHERE state = 'waiting_context'
      )
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
    WHERE id IN (
        SELECT id
        FROM pg_temp.reconcile_run_review_incompatible_executions
      )
      AND state IN (
        'queued',
        'running',
        'waiting_approval',
        'waiting_context',
        'retry_scheduled'
      )
    """)

    retired_execution_ids = """
    SELECT targets.id
    FROM pg_temp.reconcile_run_review_incompatible_executions AS targets
    JOIN agent_executions AS executions ON executions.id = targets.id
    WHERE executions.state = 'cancelled'
      AND executions.failure_code = '#{@reconciliation_failure_code}'
    """

    execute("""
    UPDATE agent_model_requests
    SET state = 'cancelled',
        failure_code = '#{@reconciliation_failure_code}',
        completed_at = COALESCE(completed_at, NOW())
    WHERE state IN ('pending', 'running', 'retry_scheduled')
      AND execution_id IN (#{retired_execution_ids})
    """)

    execute("""
    UPDATE agent_tool_requests
    SET state = 'cancelled',
        failure_code = '#{@reconciliation_failure_code}',
        completed_at = COALESCE(completed_at, NOW())
    WHERE state IN ('pending', 'running', 'retry_scheduled')
      AND execution_id IN (#{retired_execution_ids})
    """)

    execute("""
    UPDATE agent_approval_requests
    SET state = 'cancelled',
        version = version + 1,
        resolution_reason = '#{@reconciliation_failure_code}',
        resolved_at = NOW(),
        updated_at = NOW()
    WHERE state = 'pending'
      AND execution_id IN (#{retired_execution_ids})
    """)

    execute("""
    UPDATE agent_context_expansion_requests
    SET state = 'cancelled',
        version = version + 1,
        resolution_reason = '#{@reconciliation_failure_code}',
        resolved_at = NOW(),
        updated_at = NOW()
    WHERE state = 'pending'
      AND execution_id IN (#{retired_execution_ids})
    """)

    execute("DROP TABLE pg_temp.reconcile_run_review_incompatible_executions")

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

  defp incompatible_executions_sql do
    """
    SELECT executions.id, executions.state
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
