defmodule OfficeGraph.Repo.Migrations.HardenRelationshipPolicyConstraints do
  use Ecto.Migration

  def up do
    create constraint(
             :relationship_definitions,
             :relationship_definitions_provenance_policy_valid,
             check: "provenance_policy IN ('operation_required')"
           )

    create constraint(
             :relationship_definitions,
             :relationship_definitions_authorization_policy_valid,
             check: "authorization_policy IN ('authorize_scope_and_endpoints')"
           )

    create constraint(:graph_relationships, :graph_relationships_lifecycle_window_valid,
             check: """
             (lifecycle = 'active' AND valid_until IS NULL)
             OR
             (lifecycle IN ('superseded', 'archived', 'tombstoned') AND valid_until IS NOT NULL)
             """
           )
  end

  def down do
    drop constraint(:graph_relationships, :graph_relationships_lifecycle_window_valid)

    drop constraint(
           :relationship_definitions,
           :relationship_definitions_authorization_policy_valid
         )

    drop constraint(
           :relationship_definitions,
           :relationship_definitions_provenance_policy_valid
         )
  end
end
