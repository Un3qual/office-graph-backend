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

  alias OfficeGraph.{AgentRuntime, Authorization, Foundation, Repo}
  alias OfficeGraph.AgentRuntime.{AgentExecution, ExecutionWorker}
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

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

  test "reconciles canonical authority onto existing legacy binding roles" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:ok, bound} =
             AgentRuntime.bind_run_review_agent(bootstrap.session, %{
               idempotency_key: "legacy-binding-authority"
             })

    binding_id = bound.binding.id
    principal_id = bound.principal.id
    organization_id = bootstrap.organization.id
    workspace_id = bootstrap.workspace.id
    binding_id_dump = Ecto.UUID.dump!(binding_id)
    principal_id_dump = Ecto.UUID.dump!(principal_id)

    %{rows: [[system_role_id, assignment_id]]} =
      Repo.query!(
        """
        SELECT roles.id, assignments.id
        FROM agent_organization_bindings AS bindings
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
        WHERE bindings.id = $1
        """,
        [binding_id_dump]
      )

    unrelated_role_id = Ecto.UUID.generate()
    unrelated_assignment_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO roles (id, organization_id, key, name, inserted_at, updated_at)
      VALUES ($1, $2, $3, 'Unrelated agent role', NOW(), NOW())
      """,
      [
        Ecto.UUID.dump!(unrelated_role_id),
        Ecto.UUID.dump!(organization_id),
        "unrelated-agent-role-#{System.unique_integer([:positive])}"
      ]
    )

    Repo.query!(
      """
      INSERT INTO role_assignments (
        id,
        principal_id,
        role_id,
        organization_id,
        workspace_id,
        inserted_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
      """,
      [
        Ecto.UUID.dump!(unrelated_assignment_id),
        Ecto.UUID.dump!(principal_id),
        Ecto.UUID.dump!(unrelated_role_id),
        Ecto.UUID.dump!(organization_id),
        Ecto.UUID.dump!(workspace_id)
      ]
    )

    Repo.query!(
      """
      DELETE FROM role_capabilities
      WHERE role_id = $1
        AND capability_id IN (
          SELECT id
          FROM capabilities
          WHERE key IN ('agent.model.generate', 'proposal.create', 'evidence.suggest')
        )
      """,
      [system_role_id]
    )

    Repo.query!("UPDATE agent_definitions SET key = 'openspec-review' WHERE id = $1", [
      Ecto.UUID.dump!(bound.definition.id)
    ])

    assert capability_keys(system_role_id) == []
    assert capability_keys(Ecto.UUID.dump!(unrelated_role_id)) == []

    run_reconciliation_migration()
    run_reconciliation_migration()

    assert %{
             rows: [
               [
                 ^binding_id_dump,
                 ^principal_id_dump,
                 ^system_role_id,
                 ^assignment_id,
                 "active"
               ]
             ]
           } =
             Repo.query!(
               """
               SELECT
                 bindings.id,
                 bindings.agent_principal_id,
                 roles.id,
                 assignments.id,
                 bindings.lifecycle_state
               FROM agent_organization_bindings AS bindings
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
               WHERE bindings.id = $1
               """,
               [binding_id_dump]
             )

    assert capability_keys(system_role_id) ==
             ~w(agent.model.generate evidence.suggest proposal.create)

    assert capability_keys(Ecto.UUID.dump!(unrelated_role_id)) == []
  end

  test "terminalizes incompatible legacy executions before narrowing the definition" do
    context = AgentRuntimeSupport.invocation_fixture()

    compatible =
      AgentRuntimeSupport.invoke_human(context, %{
        idempotency_key: "compatible-before-reconciliation-#{context.suffix}"
      })

    Repo.query!(
      """
      UPDATE agent_definitions
      SET key = 'openspec-review',
          requested_capabilities = ARRAY[
            'agent.invoke',
            'agent.model.generate',
            'agent.tool.read',
            'evidence.suggest',
            'proposal.create',
            'repository.read'
          ]::text[],
          tool_allowlist = ARRAY['repository.read']::text[],
          updated_at = NOW()
      WHERE id = $1
      """,
      [Ecto.UUID.dump!(context.definition.id)]
    )

    Repo.query!(
      """
      INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
      SELECT
        gen_random_uuid(),
        assignments.role_id,
        capabilities.id,
        NOW(),
        NOW()
      FROM role_assignments AS assignments
      JOIN capabilities
        ON capabilities.key = ANY(ARRAY['agent.tool.read', 'repository.read']::text[])
      WHERE assignments.principal_id IN ($1, $2)
        AND assignments.organization_id = $3
        AND assignments.workspace_id = $4
      ON CONFLICT (role_id, capability_id) DO NOTHING
      """,
      [
        Ecto.UUID.dump!(context.agent_principal.id),
        Ecto.UUID.dump!(context.bootstrap.principal.id),
        Ecto.UUID.dump!(context.bootstrap.organization.id),
        Ecto.UUID.dump!(context.bootstrap.workspace.id)
      ]
    )

    legacy =
      AgentRuntimeSupport.invoke_human(context, %{
        idempotency_key: "legacy-before-reconciliation-#{context.suffix}",
        requested_capabilities: [
          "agent.model.generate",
          "agent.tool.read",
          "evidence.suggest",
          "proposal.create",
          "repository.read"
        ]
      })

    assert :ok =
             AgentRuntime.revalidate_step(legacy.execution.id,
               tool_key: "repository.read"
             )

    run_reconciliation_migration()
    run_reconciliation_migration()

    compatible_execution =
      Ash.get!(AgentExecution, compatible.execution.id, authorize?: false)

    assert compatible_execution.state == "queued"
    assert compatible_execution.state_version == compatible.execution.state_version
    assert :ok = AgentRuntime.revalidate_step(compatible_execution.id)

    legacy_execution = Ash.get!(AgentExecution, legacy.execution.id, authorize?: false)

    assert legacy_execution.state == "cancelled"
    assert legacy_execution.state_version == legacy.execution.state_version + 1
    assert legacy_execution.failure_code == "agent_definition_reconciled"
    assert %DateTime{} = legacy_execution.cancelled_at
    assert is_nil(legacy_execution.lease_token)
    assert is_nil(legacy_execution.lease_expires_at)

    [job] = AgentRuntimeSupport.execution_jobs(legacy.execution.id)

    assert {:cancel, "agent_definition_reconciled"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
  end

  defp capability_keys(role_id) do
    Repo.query!(
      """
      SELECT capabilities.key
      FROM role_capabilities
      JOIN capabilities ON capabilities.id = role_capabilities.capability_id
      WHERE role_capabilities.role_id = $1
        AND capabilities.key IN (
          'agent.model.generate',
          'proposal.create',
          'evidence.suggest'
        )
      ORDER BY capabilities.key
      """,
      [role_id]
    ).rows
    |> List.flatten()
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
