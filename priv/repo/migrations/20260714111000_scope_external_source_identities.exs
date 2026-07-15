defmodule OfficeGraph.Repo.Migrations.ScopeExternalSourceIdentities do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    drop_if_exists index(:external_sources, [:key],
                     name: :external_sources_key_index,
                     concurrently: true
                   )

    create unique_index(:external_sources, [:kind, :key],
             name: :external_sources_kind_key_index,
             concurrently: true
           )
  end

  def down do
    raise Ecto.MigrationError,
          "irreversible migration: source kinds can hold the same key after identity scoping"
  end
end
