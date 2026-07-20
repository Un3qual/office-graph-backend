agent_runtime_capability_migration_path =
  Application.app_dir(
    :office_graph,
    "priv/repo/migrations/20260720121000_backfill_agent_runtime_capabilities.exs"
  )

if File.exists?(agent_runtime_capability_migration_path) and
     not Code.ensure_loaded?(OfficeGraph.Repo.Migrations.BackfillAgentRuntimeCapabilities) do
  Code.require_file(agent_runtime_capability_migration_path)
end

defmodule OfficeGraph.AgentRuntime.OwnerCapabilityMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Repo}
  alias OfficeGraph.Authorization.Capability
  alias OfficeGraph.Repo.Migrations.BackfillAgentRuntimeCapabilities

  @migration_version 20_260_720_121_000

  test "backfills binding authority for existing owners and registers runtime execution" do
    assert Code.ensure_loaded?(BackfillAgentRuntimeCapabilities)
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    Repo.query!("""
    DELETE FROM role_capabilities
    WHERE capability_id IN (
      SELECT id FROM capabilities
      WHERE key IN ('agent.definition.bind', 'agent.runtime.execute')
    )
    """)

    Repo.query!("""
    DELETE FROM capabilities
    WHERE key IN ('agent.definition.bind', 'agent.runtime.execute')
    """)

    assert {:error, :forbidden} =
             Authorization.authorize(bootstrap.session, :agent_definition_bind,
               organization_id: bootstrap.organization.id
             )

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      BackfillAgentRuntimeCapabilities,
      :forward,
      :up,
      :up,
      log: false
    )

    assert :ok =
             Authorization.authorize(bootstrap.session, :agent_definition_bind,
               organization_id: bootstrap.organization.id
             )

    assert Ash.get!(Capability, %{key: "agent.runtime.execute"}, authorize?: false)
  end
end
