defmodule OfficeGraphWeb.RelationshipJsonTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.{Foundation, Operations}

  alias OfficeGraph.WorkGraph.{
    GraphItem,
    GraphRelationship,
    RelationshipDefinitions
  }

  test "returns the canonical safe relationship projection", %{conn: conn} do
    context = seed_cross_workspace_relationship!()

    response =
      conn
      |> Ash.PlugHelpers.set_actor(context.visible_scope.session)
      |> get(
        "/api/v1/graph-items/#{context.visible_item.id}/relationships",
        direction: "both",
        definition_keys: "references_external",
        limit: "25"
      )
      |> json_response(200)

    assert [relationship] = response["data"]
    assert relationship["type"] == "graph_relationship"
    assert relationship["id"] == context.relationship.id

    assert relationship["attributes"] == %{
             "definition_key" => "references_external",
             "family" => "external_reference",
             "direction" => "directed",
             "lifecycle" => "active",
             "governing_workspace_id" => context.visible_scope.workspace.id,
             "valid_from" => DateTime.to_iso8601(context.relationship.valid_from),
             "valid_until" => nil,
             "operation_id" => context.operation.id,
             "run_id" => nil,
             "integration_event_id" => nil,
             "supersedes_relationship_id" => nil,
             "tombstone_id" => nil,
             "source" => %{
               "visibility" => "visible",
               "id" => context.visible_item.id,
               "workspace_id" => context.visible_scope.workspace.id,
               "resource_type" => "task",
               "title" => "Visible JSON item"
             },
             "target" => %{"visibility" => "redacted"}
           }
  end

  test "rejects relationship limits outside the shared page-size contract", %{conn: conn} do
    context = seed_cross_workspace_relationship!()

    response =
      conn
      |> Ash.PlugHelpers.set_actor(context.visible_scope.session)
      |> get(
        "/api/v1/graph-items/#{context.visible_item.id}/relationships",
        limit: "101"
      )

    assert response.status == 422
  end

  defp seed_cross_workspace_relationship! do
    suffix = System.unique_integer([:positive])

    {:ok, visible_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: "Relationship JSON #{suffix}",
        organization_slug: "relationship-json-#{suffix}",
        workspace_name: "Relationship JSON Visible #{suffix}",
        workspace_slug: "relationship-json-visible-#{suffix}",
        initiative_name: "Relationship JSON Initiative #{suffix}",
        initiative_slug: "relationship-json-initiative-#{suffix}",
        owner_email: "relationship-json-#{suffix}@office-graph.local"
      )

    {:ok, hidden_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: visible_scope.organization.name,
        organization_slug: visible_scope.organization.slug,
        workspace_name: "Relationship JSON Hidden #{suffix}",
        workspace_slug: "relationship-json-hidden-#{suffix}",
        initiative_name: "Relationship JSON Hidden Initiative #{suffix}",
        initiative_slug: "relationship-json-hidden-initiative-#{suffix}",
        owner_email: visible_scope.principal.email
      )

    {:ok, operation} =
      Operations.start_operation(visible_scope.session, :graph_relationship_create)

    visible_item = insert_graph_item!(visible_scope, "task", "Visible JSON item")
    hidden_item = insert_graph_item!(hidden_scope, "external_reference", "Hidden JSON item")
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
