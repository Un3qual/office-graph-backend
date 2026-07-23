agent_capability_migration_path =
  Application.app_dir(
    :office_graph,
    "priv/repo/migrations/20260723060000_backfill_openspec_review_agent_capabilities.exs"
  )

if File.exists?(agent_capability_migration_path) and
     not Code.ensure_loaded?(OfficeGraph.Repo.Migrations.BackfillOpenSpecReviewAgentCapabilities) do
  Code.require_file(agent_capability_migration_path)
end

defmodule OfficeGraph.AgentRuntime.AgentCapabilityMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Repo}
  alias OfficeGraph.Repo.Migrations.BackfillOpenSpecReviewAgentCapabilities
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  @migration_version 20_260_723_060_000
  @capability_keys ~w(
    agent.invoke
    agent.model.generate
    agent.tool.read
    evidence.suggest
    openspec.read
    proposal.create
    repository.read
  )

  test "backfills canonical capabilities for existing OpenSpec review agents" do
    context = AgentRuntimeSupport.invocation_fixture()

    Repo.query!(
      """
      DELETE FROM role_capabilities
      WHERE role_id IN (
        SELECT role_id
        FROM role_assignments
        WHERE principal_id = $1 AND organization_id = $2 AND workspace_id = $3
      )
      AND capability_id IN (
        SELECT id FROM capabilities WHERE key = ANY($4)
      )
      """,
      [
        Ecto.UUID.dump!(context.agent_principal.id),
        Ecto.UUID.dump!(context.bootstrap.organization.id),
        Ecto.UUID.dump!(context.bootstrap.workspace.id),
        @capability_keys
      ]
    )

    assert {:ok, []} =
             Authorization.intersect_principal_capabilities(
               context.agent_principal.id,
               context.bootstrap.organization.id,
               context.bootstrap.workspace.id,
               @capability_keys
             )

    assert Code.ensure_loaded?(BackfillOpenSpecReviewAgentCapabilities)

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      BackfillOpenSpecReviewAgentCapabilities,
      :forward,
      :up,
      :up,
      log: false
    )

    assert {:ok, @capability_keys} =
             Authorization.intersect_principal_capabilities(
               context.agent_principal.id,
               context.bootstrap.organization.id,
               context.bootstrap.workspace.id,
               @capability_keys
             )
  end
end
