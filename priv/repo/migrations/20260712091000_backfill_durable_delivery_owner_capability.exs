defmodule OfficeGraph.Repo.Migrations.BackfillDurableDeliveryOwnerCapability do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    VALUES (
      md5('office_graph:capability:durable_delivery.read')::uuid,
      'durable_delivery.read',
      'durable_delivery.read',
      NOW(),
      NOW()
    )
    ON CONFLICT (key) DO NOTHING
    """)

    execute("""
    INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
    SELECT
      md5(
        'office_graph:role_capability:' || roles.id::text || ':durable_delivery.read'
      )::uuid,
      roles.id,
      capabilities.id,
      NOW(),
      NOW()
    FROM roles
    CROSS JOIN capabilities
    WHERE roles.key = 'owner'
      AND capabilities.key = 'durable_delivery.read'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)
  end

  def down do
    # The conflict-safe backfill cannot distinguish rows it inserted from
    # capability or grant rows that predated (or followed) the migration.
    # Preserve authorization data rather than destructively guessing ownership.
    :ok
  end
end
