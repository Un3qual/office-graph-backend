defmodule OfficeGraph.Repo.Migrations.AddProviderDeliveryArchives do
  use Ecto.Migration

  def up do
    alter table(:raw_archives) do
      modify :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: true,
        from: {references(:workspaces, type: :binary_id, on_delete: :restrict), null: false}

      add :archive_kind, :text, null: false, default: "manual_intake"
      add :external_delivery_id, :text
    end

    create unique_index(:raw_archives, [:source_id, :external_delivery_id],
             where: "external_delivery_id IS NOT NULL",
             name: :raw_archives_provider_delivery_index
           )

    create constraint(:raw_archives, :raw_archives_archive_kind_valid,
             check: "archive_kind IN ('manual_intake', 'provider_delivery')"
           )

    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    SELECT
      md5('office_graph:capability:' || desired.key)::uuid,
      desired.key,
      desired.key,
      NOW(),
      NOW()
    FROM (VALUES ('provider.webhook.receive'), ('integration.reconcile')) AS desired(key)
    ON CONFLICT (key) DO NOTHING
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM raw_archives WHERE workspace_id IS NULL) THEN
        RAISE EXCEPTION
          'cannot remove organization-scoped provider archives; delete or migrate them explicitly first';
      END IF;
    END
    $$
    """)

    drop constraint(:raw_archives, :raw_archives_archive_kind_valid)
    drop_if_exists index(:raw_archives, [], name: :raw_archives_provider_delivery_index)

    alter table(:raw_archives) do
      remove :external_delivery_id
      remove :archive_kind

      modify :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false,
        from: {references(:workspaces, type: :binary_id, on_delete: :restrict), null: true}
    end
  end
end
