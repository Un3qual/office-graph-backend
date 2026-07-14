defmodule OfficeGraph.Repo.Migrations.EnforceGraphRelationshipValidityStart do
  use Ecto.Migration

  def up do
    create constraint(
             :graph_relationships,
             :graph_relationships_valid_from_not_future,
             check: "valid_from <= updated_at"
           )
  end

  def down do
    drop constraint(:graph_relationships, :graph_relationships_valid_from_not_future)
  end
end
