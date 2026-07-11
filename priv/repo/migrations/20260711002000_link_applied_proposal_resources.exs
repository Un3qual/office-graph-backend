defmodule OfficeGraph.Repo.Migrations.LinkAppliedProposalResources do
  use Ecto.Migration

  def change do
    alter table(:proposed_graph_changes) do
      add :applied_resource_id, :uuid
    end
  end
end
