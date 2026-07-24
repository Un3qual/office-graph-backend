defmodule OfficeGraph.Repo.Migrations.ReconcileRunReviewDefinition do
  use Ecto.Migration

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

    execute("""
    UPDATE agent_definitions
    SET name = 'Run Review',
        description = 'Reviews authorized Office Graph run context and proposes bounded follow-up.',
        supported_modes = ARRAY['human', 'automatic']::text[],
        requested_capabilities = ARRAY[
          'agent.invoke',
          'agent.model.generate',
          'proposal.create',
          'evidence.suggest'
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
  end

  def down do
    # The canonical definition key and approved configuration are retained.
    :ok
  end
end
