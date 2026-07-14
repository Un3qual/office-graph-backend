defmodule OfficeGraph.WorkGraph.RelationshipCommandsTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Operations, WorkGraph}
  alias OfficeGraph.WorkGraph.{GraphItem, GraphRelationship, RelationshipRequest}

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_name: "Relationship Commands #{suffix}",
        organization_slug: "relationship-commands-#{suffix}",
        workspace_name: "Relationship Commands Workspace #{suffix}",
        workspace_slug: "relationship-commands-workspace-#{suffix}",
        initiative_name: "Relationship Commands Initiative #{suffix}",
        initiative_slug: "relationship-commands-initiative-#{suffix}",
        owner_email: "relationship-commands-#{suffix}@office-graph.local"
      )

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :graph_relationship_create)

    task_item = insert_graph_item!(bootstrap, "task", "Command task")
    other_task_item = insert_graph_item!(bootstrap, "task", "Other command task")

    review_finding_item =
      insert_graph_item!(bootstrap, "review_finding", "Command review finding")

    %{
      bootstrap: bootstrap,
      session: bootstrap.session,
      operation: operation,
      task_item: task_item,
      other_task_item: other_task_item,
      review_finding_item: review_finding_item
    }
  end

  test "create validates endpoints and replays one active edge", context do
    request = %RelationshipRequest{
      definition_key: "review_finding_for",
      source_item_id: context.review_finding_item.id,
      target_item_id: context.task_item.id,
      workspace_id: context.session.workspace_id
    }

    assert {:ok, first} =
             WorkGraph.create_relationship(context.session, context.operation, request)

    assert {:ok, replay} =
             WorkGraph.create_relationship(context.session, context.operation, request)

    assert replay.id == first.id
    assert replay.lifecycle == "active"
    assert replay.operation_id == context.operation.id
    assert replay.asserting_principal_id == context.session.principal_id

    reversed = %{
      request
      | source_item_id: request.target_item_id,
        target_item_id: request.source_item_id
    }

    assert {:error, {:invalid_relationship_endpoints, "review_finding_for"}} =
             WorkGraph.create_relationship(context.session, context.operation, reversed)
  end

  test "wrong operations and cross-workspace requests are forbidden", context do
    request =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: context.task_item.id,
        target_item_id: context.other_task_item.id,
        workspace_id: context.session.workspace_id
      })

    {:ok, wrong_operation} =
      Operations.start_operation(context.session, :manual_intake_submit)

    assert {:error, :forbidden} =
             WorkGraph.create_relationship(context.session, wrong_operation, request)

    {:ok, other_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: context.bootstrap.organization.name,
        organization_slug: context.bootstrap.organization.slug,
        workspace_name: "Relationship Commands Other Workspace",
        workspace_slug: "relationship-commands-other-#{System.unique_integer([:positive])}",
        initiative_name: "Relationship Commands Other Initiative",
        initiative_slug: "relationship-commands-other-#{System.unique_integer([:positive])}",
        owner_email: context.bootstrap.principal.email
      )

    other_workspace_item =
      insert_graph_item!(other_scope, "task", "Cross-workspace command task")

    cross_workspace_request = %{
      request
      | target_item_id: other_workspace_item.id
    }

    assert {:error, :forbidden} =
             WorkGraph.create_relationship(
               context.session,
               context.operation,
               cross_workspace_request
             )
  end

  test "archive and restore preserve one relationship identity", context do
    request =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: context.task_item.id,
        target_item_id: context.other_task_item.id,
        workspace_id: context.session.workspace_id
      })

    assert {:ok, relationship} =
             WorkGraph.create_relationship(context.session, context.operation, request)

    {:ok, archive_operation} =
      Operations.start_operation(context.session, :graph_relationship_archive)

    assert {:ok, archived} =
             WorkGraph.archive_relationship(
               context.session,
               archive_operation,
               relationship,
               %{}
             )

    assert archived.id == relationship.id
    assert archived.lifecycle == "archived"
    assert %DateTime{} = archived.valid_until

    {:ok, restore_operation} =
      Operations.start_operation(context.session, :graph_relationship_restore)

    assert {:ok, restored} =
             WorkGraph.restore_relationship(
               context.session,
               restore_operation,
               archived,
               %{}
             )

    assert restored.id == relationship.id
    assert restored.lifecycle == "active"
    assert restored.operation_id == restore_operation.id
    assert is_nil(restored.valid_until)
  end

  test "supersede keeps the old edge and links the active replacement", context do
    third_task_item = insert_graph_item!(context.bootstrap, "task", "Third command task")

    original_request =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: context.task_item.id,
        target_item_id: context.other_task_item.id,
        workspace_id: context.session.workspace_id
      })

    replacement_request = %{
      original_request
      | target_item_id: third_task_item.id
    }

    assert {:ok, original} =
             WorkGraph.create_relationship(
               context.session,
               context.operation,
               original_request
             )

    {:ok, supersede_operation} =
      Operations.start_operation(context.session, :graph_relationship_supersede)

    assert {:ok, replacement} =
             WorkGraph.supersede_relationship(
               context.session,
               supersede_operation,
               original,
               replacement_request
             )

    assert replacement.lifecycle == "active"
    assert replacement.supersedes_relationship_id == original.id

    persisted_original = Ash.get!(GraphRelationship, original.id, authorize?: false)
    assert persisted_original.lifecycle == "superseded"
    assert %DateTime{} = persisted_original.valid_until
  end

  test "relationship resource exposes no direct public mutations" do
    public_mutations =
      GraphRelationship
      |> Ash.Resource.Info.public_actions()
      |> Enum.filter(&(&1.type in [:create, :update, :destroy]))

    assert public_mutations == []
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
end
