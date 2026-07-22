delegation_capability_migration_path =
  Application.app_dir(
    :office_graph,
    "priv/repo/migrations/20260722181000_backfill_agent_runtime_delegation_capabilities.exs"
  )

if File.exists?(delegation_capability_migration_path) and
     not Code.ensure_loaded?(
       OfficeGraph.Repo.Migrations.BackfillAgentRuntimeDelegationCapabilities
     ) do
  Code.require_file(delegation_capability_migration_path)
end

defmodule OfficeGraph.AgentRuntime.DelegationCapabilityMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Repo}
  alias OfficeGraph.Repo.Migrations.BackfillAgentRuntimeDelegationCapabilities

  @migration_version 20_260_722_181_000
  @capability_keys ~w(
    agent.model.generate
    agent.tool.read
    evidence.suggest
    openspec.read
    proposal.create
    repository.read
  )

  test "backfills canonical agent delegation capabilities for existing owners" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    Repo.query!(
      """
      DELETE FROM role_capabilities
      WHERE capability_id IN (SELECT id FROM capabilities WHERE key = ANY($1))
      """,
      [@capability_keys]
    )

    Repo.query!("DELETE FROM capabilities WHERE key = ANY($1)", [@capability_keys])

    assert {:ok, []} =
             Authorization.intersect_principal_capabilities(
               bootstrap.principal.id,
               bootstrap.organization.id,
               bootstrap.workspace.id,
               @capability_keys
             )

    assert Code.ensure_loaded?(BackfillAgentRuntimeDelegationCapabilities)

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      BackfillAgentRuntimeDelegationCapabilities,
      :forward,
      :up,
      :up,
      log: false
    )

    assert {:ok, @capability_keys} =
             Authorization.intersect_principal_capabilities(
               bootstrap.principal.id,
               bootstrap.organization.id,
               bootstrap.workspace.id,
               @capability_keys
             )
  end
end
