defmodule OfficeGraph.Authorization.OwnerRelationshipCapabilityMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Repo}

  @capability_actions [
    graph_relationship_create: "graph_relationship.create",
    graph_relationship_supersede: "graph_relationship.supersede",
    graph_relationship_archive: "graph_relationship.archive",
    graph_relationship_restore: "graph_relationship.restore"
  ]
  @migration_version 20_260_713_102_000
  @migration_module OfficeGraph.Repo.Migrations.BackfillGraphRelationshipOwnerCapabilities

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

    path =
      Application.app_dir(
        :office_graph,
        "priv/repo/migrations/20260713102000_backfill_graph_relationship_owner_capabilities.exs"
      )

    assert File.exists?(path), "relationship capability backfill migration is missing"
    Code.require_file(path)

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      @migration_module,
      :forward,
      :up,
      :up,
      log: false
    )

    for {action, _key} <- @capability_actions do
      assert :ok =
               Authorization.authorize(bootstrap.session, action,
                 organization_id: bootstrap.organization.id
               )
    end
  end
end
