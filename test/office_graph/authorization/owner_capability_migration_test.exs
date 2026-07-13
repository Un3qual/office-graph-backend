unless Code.ensure_loaded?(OfficeGraph.Repo.Migrations.BackfillDurableDeliveryOwnerCapability) do
  Code.require_file(
    Application.app_dir(
      :office_graph,
      "priv/repo/migrations/20260712091000_backfill_durable_delivery_owner_capability.exs"
    )
  )
end

defmodule OfficeGraph.Authorization.OwnerCapabilityMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Repo}
  alias OfficeGraph.Repo.Migrations.BackfillDurableDeliveryOwnerCapability

  @migration_version 20_260_712_091_000

  test "grants durable delivery reads to owner roles created before the capability existed" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert :ok =
             Authorization.authorize(bootstrap.session, :durable_delivery_read,
               organization_id: bootstrap.organization.id
             )

    Repo.query!("""
    DELETE FROM role_capabilities
    WHERE capability_id IN (
      SELECT id FROM capabilities WHERE key = 'durable_delivery.read'
    )
    """)

    Repo.query!("DELETE FROM capabilities WHERE key = 'durable_delivery.read'")

    assert {:error, :forbidden} =
             Authorization.authorize(bootstrap.session, :durable_delivery_read,
               organization_id: bootstrap.organization.id
             )

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      BackfillDurableDeliveryOwnerCapability,
      :forward,
      :up,
      :up,
      log: false
    )

    assert :ok =
             Authorization.authorize(bootstrap.session, :durable_delivery_read,
               organization_id: bootstrap.organization.id
             )
  end
end
