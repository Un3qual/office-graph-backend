defmodule OfficeGraphWeb.RelationshipGraphqlTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.{Foundation, Operations}

  alias OfficeGraph.WorkGraph.{
    GraphItem,
    GraphRelationship,
    RelationshipDefinitions
  }

  test "returns Relay-stable canonical relationships with redacted endpoints", %{conn: conn} do
    context = seed_cross_workspace_relationship!()

    response =
      conn
      |> Ash.PlugHelpers.set_actor(context.visible_scope.session)
      |> post(~p"/graphql", %{
        query: relationship_query(),
        variables: %{
          "itemId" => context.visible_item.id,
          "direction" => "BOTH",
          "definitionKeys" => ["references_external"],
          "limit" => 25
        }
      })
      |> json_response(200)

    assert response["errors"] in [nil, []]
    assert [relationship] = response["data"]["graphRelationships"]

    assert {:ok, %{type: :graph_relationship_view, id: relationship_id}} =
             Absinthe.Relay.Node.from_global_id(
               relationship["id"],
               OfficeGraphWeb.GraphQL.Schema
             )

    assert relationship_id == context.relationship.id
    assert relationship["definitionKey"] == "references_external"
    assert relationship["family"] == "external_reference"
    assert relationship["direction"] == "directed"
    assert relationship["lifecycle"] == "active"
    assert relationship["operationId"] == context.operation.id

    assert relationship["source"]["visibility"] == "visible"

    assert {:ok, "GraphItem", source_id} =
             OfficeGraphWeb.GraphQL.RelayIdTranslator.from_global_id(
               relationship["source"]["id"],
               OfficeGraphWeb.GraphQL.Schema
             )

    assert source_id == context.visible_item.id
    assert relationship["target"] == %{"visibility" => "redacted", "id" => nil}

    node_response =
      conn
      |> recycle()
      |> Ash.PlugHelpers.set_actor(context.visible_scope.session)
      |> post(~p"/graphql", %{
        query: relationship_node_query(),
        variables: %{"id" => relationship["id"]}
      })
      |> json_response(200)

    assert node_response["errors"] in [nil, []]

    assert node_response["data"]["node"] == %{
             "id" => relationship["id"],
             "definitionKey" => "references_external",
             "target" => %{"visibility" => "redacted", "id" => nil}
           }
  end

  defp relationship_query do
    """
    query RelationshipGraph(
      $itemId: ID!
      $direction: String
      $definitionKeys: [String!]
      $limit: Int
    ) {
      graphRelationships(
        itemId: $itemId
        direction: $direction
        definitionKeys: $definitionKeys
        limit: $limit
      ) {
        id
        definitionKey
        family
        direction
        lifecycle
        governingWorkspaceId
        validFrom
        validUntil
        operationId
        runId
        integrationEventId
        supersedesRelationshipId
        tombstoneId
        source { visibility id }
        target { visibility id }
      }
    }
    """
  end

  defp relationship_node_query do
    """
    query RelationshipNode($id: ID!) {
      node(id: $id) {
        id
        ... on GraphRelationshipView {
          definitionKey
          target { visibility id }
        }
      }
    }
    """
  end

  defp seed_cross_workspace_relationship! do
    suffix = System.unique_integer([:positive])

    {:ok, visible_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: "Relationship GraphQL #{suffix}",
        organization_slug: "relationship-graphql-#{suffix}",
        workspace_name: "Relationship GraphQL Visible #{suffix}",
        workspace_slug: "relationship-graphql-visible-#{suffix}",
        initiative_name: "Relationship GraphQL Initiative #{suffix}",
        initiative_slug: "relationship-graphql-initiative-#{suffix}",
        owner_email: "relationship-graphql-#{suffix}@office-graph.local"
      )

    {:ok, hidden_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: visible_scope.organization.name,
        organization_slug: visible_scope.organization.slug,
        workspace_name: "Relationship GraphQL Hidden #{suffix}",
        workspace_slug: "relationship-graphql-hidden-#{suffix}",
        initiative_name: "Relationship GraphQL Hidden Initiative #{suffix}",
        initiative_slug: "relationship-graphql-hidden-initiative-#{suffix}",
        owner_email: visible_scope.principal.email
      )

    {:ok, operation} =
      Operations.start_operation(visible_scope.session, :graph_relationship_create)

    visible_item = insert_graph_item!(visible_scope, "task", "Visible GraphQL item")
    hidden_item = insert_graph_item!(hidden_scope, "external_reference", "Hidden GraphQL item")
    {:ok, definition} = RelationshipDefinitions.fetch_by_key("references_external")

    relationship =
      Ash.create!(
        GraphRelationship,
        %{
          id: Ecto.UUID.generate(),
          definition_id: definition.id,
          organization_id: visible_scope.organization.id,
          workspace_id: visible_scope.workspace.id,
          source_item_id: visible_item.id,
          target_item_id: hidden_item.id,
          lifecycle: "active",
          asserting_principal_id: visible_scope.principal.id,
          operation_id: operation.id,
          valid_from: DateTime.utc_now()
        },
        action: :create,
        authorize?: false
      )

    %{
      visible_scope: visible_scope,
      operation: operation,
      visible_item: visible_item,
      relationship: relationship
    }
  end

  defp insert_graph_item!(scope, resource_type, title) do
    Ash.create!(
      GraphItem,
      %{
        id: Ecto.UUID.generate(),
        organization_id: scope.organization.id,
        workspace_id: scope.workspace.id,
        resource_type: resource_type,
        resource_id: Ecto.UUID.generate(),
        title: title
      },
      action: :create,
      authorize?: false
    )
  end
end
