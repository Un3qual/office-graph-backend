defmodule OfficeGraph.Repo.Migrations.WidenSubjectVersions do
  use Ecto.Migration

  def up do
    alter table(:operation_correlations) do
      modify :subject_version, :bigint, from: :integer
    end

    alter table(:domain_events) do
      modify :subject_version, :bigint, from: :integer
    end
  end

  def down do
    raise Ecto.MigrationError,
          "irreversible migration: 64-bit subject versions may exceed the prior integer range"
  end
end
