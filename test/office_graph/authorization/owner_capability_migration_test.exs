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
  alias OfficeGraph.Authorization.{Capability, Role, RoleCapability}
  alias OfficeGraph.Repo.Migrations.BackfillDurableDeliveryOwnerCapability

  require Ash.Query

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

  test "rollback preserves pre-existing capability and grants" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    capability = Ash.get!(Capability, %{key: "durable_delivery.read"}, authorize?: false)

    owner_role =
      Role
      |> Ash.Query.filter(organization_id == ^bootstrap.organization.id and key == "owner")
      |> Ash.read_one!(authorize?: false)

    {:ok, non_owner_role} =
      Ash.create(
        Role,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          key: "durable-delivery-auditor",
          name: "Durable Delivery Auditor"
        },
        action: :create,
        authorize?: false
      )

    {:ok, non_owner_grant} =
      Ash.create(
        RoleCapability,
        %{
          id: Ecto.UUID.generate(),
          role_id: non_owner_role.id,
          capability_id: capability.id
        },
        action: :create,
        authorize?: false
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

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      BackfillDurableDeliveryOwnerCapability,
      :forward,
      :down,
      :down,
      log: false
    )

    assert Ash.get!(Capability, capability.id, authorize?: false).key == "durable_delivery.read"

    assert Ash.get!(RoleCapability, non_owner_grant.id, authorize?: false).id ==
             non_owner_grant.id

    assert RoleCapability
           |> Ash.Query.filter(role_id == ^owner_role.id and capability_id == ^capability.id)
           |> Ash.exists?(authorize?: false)
  end
end
