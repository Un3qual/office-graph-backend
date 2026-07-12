defmodule OfficeGraph.Repo.Migrations.AddPacketSourceProjectionIndex do
  use Ecto.Migration

  @index_name :work_packet_version_sources_scope_graph_item_version_index

  def up do
    create index(
             :work_packet_version_sources,
             [:organization_id, :workspace_id, :graph_item_id, :work_packet_version_id],
             name: @index_name
           )
  end

  def down do
    drop_if_exists index(:work_packet_version_sources, [], name: @index_name)
  end
end
