defmodule OfficeGraph.Repo.Migrations.ScopeExternalSourceIdentities do
  use Ecto.Migration

  def up do
    drop_if_exists index(:external_sources, [], name: :external_sources_key_index)

    create unique_index(:external_sources, [:kind, :key], name: :external_sources_kind_key_index)
  end

  def down do
    raise Ecto.MigrationError,
          "irreversible migration: source kinds can hold the same key after identity scoping"
  end
end
