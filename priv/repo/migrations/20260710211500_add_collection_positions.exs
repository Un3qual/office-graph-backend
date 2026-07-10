defmodule OfficeGraph.Repo.Migrations.AddCollectionPositions do
  use Ecto.Migration

  def change do
    alter table(:work_packet_version_sources) do
      add :position, :integer, null: false, default: 0
    end

    alter table(:work_packet_version_required_checks) do
      add :position, :integer, null: false, default: 0
    end

    alter table(:run_required_checks) do
      add :position, :integer, null: false, default: 0
    end
  end
end
