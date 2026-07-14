defmodule OfficeGraph.Authorization.OwnerRelationshipCapabilityMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Repo}
  alias OfficeGraph.Authorization.Capability

  @capability_actions [
    graph_relationship_create: "graph_relationship.create",
    graph_relationship_supersede: "graph_relationship.supersede",
    graph_relationship_archive: "graph_relationship.archive",
    graph_relationship_restore: "graph_relationship.restore"
  ]
  @owner_migration_version 20_260_713_102_000
  @owner_migration_module OfficeGraph.Repo.Migrations.BackfillGraphRelationshipOwnerCapabilities
  @restricted_migration_version 20_260_713_105_000

  @restricted_migration_module OfficeGraph.Repo.Migrations.SeedGraphRelationshipCrossWorkspaceCapability

  test "grants relationship commands to owner roles created before the capabilities existed" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    capability_keys = Keyword.values(@capability_actions)

    Repo.query!(
      """
      DELETE FROM role_capabilities
      WHERE capability_id IN (
        SELECT id FROM capabilities WHERE key = ANY($1)
      )
      """,
      [capability_keys]
    )

    Repo.query!("DELETE FROM capabilities WHERE key = ANY($1)", [capability_keys])

    for {action, _key} <- @capability_actions do
      assert {:error, :forbidden} =
               Authorization.authorize(bootstrap.session, action,
                 organization_id: bootstrap.organization.id
               )
    end

    run_migration!(
      @owner_migration_version,
      @owner_migration_module,
      "20260713102000_backfill_graph_relationship_owner_capabilities.exs"
    )

    for {action, _key} <- @capability_actions do
      assert :ok =
               Authorization.authorize(bootstrap.session, action,
                 organization_id: bootstrap.organization.id
               )
    end
  end

  test "seeds the restricted cross-workspace capability without granting it to owners" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    action = :graph_relationship_cross_workspace
    key = "graph_relationship.cross_workspace"

    Repo.query!(
      "DELETE FROM role_capabilities WHERE capability_id IN (SELECT id FROM capabilities WHERE key = $1)",
      [key]
    )

    Repo.query!("DELETE FROM capabilities WHERE key = $1", [key])

    assert {:error, _not_found} = Ash.get(Capability, %{key: key}, authorize?: false)

    run_migration!(
      @restricted_migration_version,
      @restricted_migration_module,
      "20260713105000_seed_graph_relationship_cross_workspace_capability.exs"
    )

    assert Ash.get!(Capability, %{key: key}, authorize?: false)

    assert {:error, :forbidden} =
             Authorization.authorize(bootstrap.session, action,
               organization_id: bootstrap.organization.id
             )
  end

  defp run_migration!(version, module, filename) do
    path = Application.app_dir(:office_graph, "priv/repo/migrations/#{filename}")

    assert File.exists?(path), "relationship capability migration is missing"
    Code.require_file(path)

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      version,
      module,
      :forward,
      :up,
      :up,
      log: false
    )
  end
end
