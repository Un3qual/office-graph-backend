unless Code.ensure_loaded?(OfficeGraph.Repo.Migrations.BackfillAgentRuntimeGovernance) do
  Code.require_file(
    Application.app_dir(
      :office_graph,
      "priv/repo/migrations/20260721230000_backfill_agent_runtime_governance.exs"
    )
  )
end

defmodule OfficeGraph.AgentRuntime.GovernanceMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Repo}
  alias OfficeGraph.Repo.Migrations.BackfillAgentRuntimeGovernance

  @migration_version 20_260_721_230_000

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
    WHERE key = 'openspec-review'
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
             WHERE key = 'openspec-review'
             """)

    assert Enum.sort(allowed_output_kinds) ==
             ~w(evidence_candidate finding message observation proposal)
  end
end
