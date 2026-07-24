unless Code.ensure_loaded?(OfficeGraph.Repo.Migrations.BackfillAgentRuntimeGovernance) do
  Code.require_file(
    Application.app_dir(
      :office_graph,
      "priv/repo/migrations/20260721230000_backfill_agent_runtime_governance.exs"
    )
  )
end

reconciliation_migration =
  Application.app_dir(
    :office_graph,
    "priv/repo/migrations/20260723220000_reconcile_run_review_definition.exs"
  )

if File.exists?(reconciliation_migration) and
     not Code.ensure_loaded?(OfficeGraph.Repo.Migrations.ReconcileRunReviewDefinition) do
  Code.require_file(reconciliation_migration)
end

defmodule OfficeGraph.AgentRuntime.GovernanceMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Repo}

  alias OfficeGraph.Repo.Migrations.{
    BackfillAgentRuntimeGovernance,
    ReconcileRunReviewDefinition
  }

  @migration_version 20_260_721_230_000
  @reconciliation_migration_version 20_260_723_220_000

  test "backfills invocation authority for owners and aligns the canonical output allowlist" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    Repo.query!("""
    DELETE FROM role_capabilities
    WHERE capability_id IN (SELECT id FROM capabilities WHERE key = 'agent.invoke')
    """)

    Repo.query!("DELETE FROM capabilities WHERE key = 'agent.invoke'")

    Repo.query!("""
    UPDATE agent_definitions
    SET allowed_output_kinds = ARRAY['message']::text[]
    WHERE key = 'run-review'
    """)

    assert {:error, :forbidden} =
             Authorization.authorize(bootstrap.session, :agent_invoke,
               organization_id: bootstrap.organization.id,
               workspace_id: bootstrap.workspace.id
             )

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      BackfillAgentRuntimeGovernance,
      :forward,
      :up,
      :up,
      log: false
    )

    assert :ok =
             Authorization.authorize(bootstrap.session, :agent_invoke,
               organization_id: bootstrap.organization.id,
               workspace_id: bootstrap.workspace.id
             )

    assert %{rows: [[allowed_output_kinds]]} =
             Repo.query!("""
             SELECT allowed_output_kinds
             FROM agent_definitions
             WHERE key = 'run-review'
             """)

    assert Enum.sort(allowed_output_kinds) ==
             ~w(evidence_candidate finding message observation proposal)
  end

  test "reconciles the legacy definition in place with the canonical runtime contract" do
    %{rows: [[definition_id]]} =
      Repo.query!("SELECT id FROM agent_definitions WHERE key = 'run-review'")

    Repo.query!(
      """
      UPDATE agent_definitions
      SET key = 'openspec-review',
          name = 'Legacy Review',
          description = 'legacy',
          lifecycle_state = 'disabled',
          supported_modes = ARRAY['human']::text[],
          requested_capabilities = ARRAY['agent.invoke']::text[],
          model_adapter_key = 'legacy',
          tool_allowlist = ARRAY['legacy.tool']::text[],
          default_autonomy_mode = 'bounded_automatic',
          allowed_output_kinds = ARRAY['message']::text[]
      WHERE id = $1
      """,
      [definition_id]
    )

    run_reconciliation_migration()
    run_reconciliation_migration()

    assert %{
             rows: [
               [
                 ^definition_id,
                 "run-review",
                 "Run Review",
                 "disabled",
                 ["human", "automatic"],
                 requested_capabilities,
                 "deterministic",
                 [],
                 "human_supervised",
                 allowed_output_kinds
               ]
             ]
           } =
             Repo.query!("""
             SELECT
               id,
               key,
               name,
               lifecycle_state,
               supported_modes,
               requested_capabilities,
               model_adapter_key,
               tool_allowlist,
               default_autonomy_mode,
               allowed_output_kinds
             FROM agent_definitions
             WHERE key = 'run-review'
             """)

    assert Enum.sort(requested_capabilities) ==
             ~w(agent.invoke agent.model.generate evidence.suggest proposal.create)

    assert Enum.sort(allowed_output_kinds) ==
             ~w(evidence_candidate finding message observation proposal)

    refute Repo.exists?(
             from definition in "agent_definitions",
               where: definition.key == "openspec-review",
               select: true
           )
  end

  defp run_reconciliation_migration do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @reconciliation_migration_version,
      ReconcileRunReviewDefinition,
      :forward,
      :up,
      :up,
      log: false
    )
  end
end
