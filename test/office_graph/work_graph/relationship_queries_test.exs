defmodule OfficeGraph.WorkGraph.RelationshipQueriesTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Operations, QueryCounter, WorkGraph}

  alias OfficeGraph.WorkGraph.{
    GraphItem,
    GraphRelationship,
    RelationshipDefinitions
  }

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, visible_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: "Relationship Reads #{suffix}",
        organization_slug: "relationship-reads-#{suffix}",
        workspace_name: "Visible Relationship Workspace #{suffix}",
        workspace_slug: "visible-relationship-workspace-#{suffix}",
        initiative_name: "Visible Relationship Initiative #{suffix}",
        initiative_slug: "visible-relationship-initiative-#{suffix}",
        owner_email: "relationship-reads-#{suffix}@office-graph.local"
      )

    {:ok, hidden_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: visible_scope.organization.name,
        organization_slug: visible_scope.organization.slug,
        workspace_name: "Hidden Relationship Workspace #{suffix}",
        workspace_slug: "hidden-relationship-workspace-#{suffix}",
        initiative_name: "Hidden Relationship Initiative #{suffix}",
        initiative_slug: "hidden-relationship-initiative-#{suffix}",
        owner_email: visible_scope.principal.email
      )

    {:ok, operation} =
      Operations.start_operation(visible_scope.session, :graph_relationship_create)

    visible_item = insert_graph_item!(visible_scope, "task", "Visible relationship item")

    hidden_item =
      insert_graph_item!(hidden_scope, "external_reference", "Hidden relationship item")

    relationship =
      insert_relationship!(
        visible_scope,
        operation,
        "references_external",
        visible_item,
        hidden_item
      )

    %{
      visible_scope: visible_scope,
      hidden_scope: hidden_scope,
      operation: operation,
      visible_item: visible_item,
      hidden_item: hidden_item,
      relationship: relationship
    }
  end

  test "adjacency returns canonical metadata and redacts an unauthorized endpoint", context do
    assert {:ok, [view]} =
             WorkGraph.list_relationships(context.visible_scope.session, context.visible_item.id,
               direction: :both,
               limit: 25
             )

    assert view.id == context.relationship.id
    assert view.definition_key == "references_external"
    assert view.family == "external_reference"
    assert view.direction == "directed"
    assert view.lifecycle == "active"
    assert view.governing_workspace_id == context.visible_scope.workspace.id
    assert view.operation_id == context.operation.id
    assert %DateTime{} = view.valid_from
    assert is_nil(view.valid_until)

    assert view.source == %{
             visibility: :visible,
             id: context.visible_item.id,
             workspace_id: context.visible_scope.workspace.id,
             resource_type: "task",
             title: "Visible relationship item"
           }

    assert view.target == %{visibility: :redacted}
  end

  test "direction, definition, lifecycle, and limit filters are applied before projection",
       context do
    second_target = insert_graph_item!(context.visible_scope, "task", "Second relationship item")

    _relationship =
      insert_relationship!(
        context.visible_scope,
        context.operation,
        "depends_on",
        context.visible_item,
        second_target
      )

    assert {:ok, [depends_on]} =
             WorkGraph.list_relationships(context.visible_scope.session, context.visible_item.id,
               direction: :outgoing,
               definition_keys: ["depends_on"],
               lifecycle: "active",
               limit: 1
             )

    assert depends_on.definition_key == "depends_on"
    assert depends_on.target.visibility == :visible

    assert {:ok, []} =
             WorkGraph.list_relationships(context.visible_scope.session, context.visible_item.id,
               direction: :incoming,
               definition_keys: ["depends_on"],
               limit: 100
             )
  end

  test "bounded adjacency does not add one query per edge", context do
    Enum.each(1..40, fn index ->
      target =
        insert_graph_item!(context.visible_scope, "task", "Relationship fanout #{index}")

      insert_relationship!(
        context.visible_scope,
        context.operation,
        "depends_on",
        context.visible_item,
        target
      )
    end)

    {result, queries} =
      QueryCounter.count(fn ->
        WorkGraph.list_relationships(context.visible_scope.session, context.visible_item.id,
          direction: :outgoing,
          definition_keys: ["depends_on"],
          limit: 40
        )
      end)

    assert {:ok, views} = result
    assert length(views) == 40
    assert length(queries) <= 6
    assert QueryCounter.source_count(queries, "graph_relationships") <= 1
    assert QueryCounter.source_count(queries, "graph_items") <= 2
  end

  test "an actor cannot enumerate adjacency through an unauthorized anchor item", context do
    assert {:error, :forbidden} =
             WorkGraph.list_relationships(
               context.hidden_scope.session,
               context.visible_item.id,
               direction: :both
             )
  end

  defp insert_graph_item!(bootstrap, resource_type, title) do
    Ash.create!(
      GraphItem,
      %{
        id: Ecto.UUID.generate(),
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        resource_type: resource_type,
        resource_id: Ecto.UUID.generate(),
        title: title
      },
      action: :create,
      authorize?: false
    )
  end

  defp insert_relationship!(bootstrap, operation, definition_key, source, target) do
    {:ok, definition} = RelationshipDefinitions.fetch_by_key(definition_key)

    Ash.create!(
      GraphRelationship,
      %{
        id: Ecto.UUID.generate(),
        definition_id: definition.id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        source_item_id: source.id,
        target_item_id: target.id,
        lifecycle: "active",
        asserting_principal_id: bootstrap.principal.id,
        operation_id: operation.id,
        valid_from: DateTime.utc_now()
      },
      action: :create,
      authorize?: false
    )
  end
end
