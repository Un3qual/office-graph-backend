defmodule OfficeGraph.Repo.Migrations.AddPacketVersionTitles do
  use Ecto.Migration

  def up do
    alter table(:work_packet_versions) do
      add :title, :text
    end

    execute """
    UPDATE work_packet_versions AS versions
    SET title = packets.title
    FROM work_packets AS packets
    WHERE versions.work_packet_id = packets.id
    """

    alter table(:work_packet_versions) do
      modify :title, :text, null: false
    end
  end

  def down do
    alter table(:work_packet_versions) do
      remove :title
    end
  end
end
