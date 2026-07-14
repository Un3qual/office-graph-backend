defmodule OfficeGraph.WorkGraph.GraphRelationshipTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.WorkGraph.GraphRelationship

  test "resource exposes typed scope, lifecycle, and provenance instead of a free-form type" do
    attribute_names = GraphRelationship |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

    for attribute <- [
          :definition_id,
          :organization_id,
          :workspace_id,
          :lifecycle,
          :asserting_principal_id,
          :operation_id,
          :valid_from,
          :valid_until,
          :run_id,
          :integration_event_id,
          :supersedes_relationship_id,
          :tombstone_id
        ] do
      assert attribute in attribute_names
    end

    refute :relationship_type in attribute_names
    refute :metadata in attribute_names

    create = Ash.Resource.Info.action(GraphRelationship, :create)
    refute :relationship_type in create.accept
    refute :metadata in create.accept
    refute :lifecycle in create.accept
    refute :valid_until in create.accept

    for action_name <- [:mark_superseded, :archive] do
      action = Ash.Resource.Info.action(GraphRelationship, action_name)
      refute :valid_until in action.accept
    end

    lifecycle = Ash.Resource.Info.attribute(GraphRelationship, :lifecycle)

    for value <- ["active", "superseded", "archived", "tombstoned"] do
      assert {:ok, ^value} = Ash.Type.apply_constraints(:string, value, lifecycle.constraints)
    end

    assert {:error, _error} =
             Ash.Type.apply_constraints(:string, "invented", lifecycle.constraints)

    assert [:organization_id, :definition_id, :source_item_id, :target_item_id] ==
             Ash.Resource.Info.identity(GraphRelationship, :active_definition_edge).keys
  end

  test "typed foreign keys are modeled as Ash relationships" do
    relationships =
      GraphRelationship
      |> Ash.Resource.Info.relationships()
      |> Map.new(&{&1.name, &1.destination})

    assert relationships.definition == OfficeGraph.WorkGraph.RelationshipDefinition
    assert relationships.organization == OfficeGraph.Tenancy.Organization
    assert relationships.governing_workspace == OfficeGraph.Tenancy.Workspace
    assert relationships.operation == OfficeGraph.Operations.OperationCorrelation
    assert relationships.asserting_principal == OfficeGraph.Identity.Principal
    assert relationships.superseded_relationship == GraphRelationship
    assert relationships.tombstone == OfficeGraph.Tombstones.Tombstone

    refute Map.has_key?(relationships, :related_run)
    refute Map.has_key?(relationships, :integration_event)
  end
end
