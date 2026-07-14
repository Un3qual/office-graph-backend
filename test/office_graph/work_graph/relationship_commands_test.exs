defmodule OfficeGraph.WorkGraph.RelationshipCommandsTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Integrations, Operations, WorkGraph}
  alias OfficeGraph.Authorization.Capability
  alias OfficeGraph.WorkGraph.{GraphItem, GraphRelationship, RelationshipRequest}

  import OfficeGraph.TestSupport.WorkPacketCommandLoopSupport,
    only: [create_ready_run: 2, create_required_verification_check: 1]

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

    second_other_workspace_item =
      insert_graph_item!(other_scope, "task", "Second cross-workspace command task")

    remote_only_request = %{
      request
      | source_item_id: other_workspace_item.id,
        target_item_id: second_other_workspace_item.id
    }

    assert {:error, :forbidden} =
             WorkGraph.create_relationship(
               context.session,
               context.operation,
               remote_only_request
             )
  end

  test "cross-workspace capability preserves governing scope without granting target access",
       context do
    ensure_cross_workspace_capability!()

    {:ok, other_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: context.bootstrap.organization.name,
        organization_slug: context.bootstrap.organization.slug,
        workspace_name: "Authorized Relationship Commands Other Workspace",
        workspace_slug:
          "authorized-relationship-commands-other-#{System.unique_integer([:positive])}",
        initiative_name: "Authorized Relationship Commands Other Initiative",
        initiative_slug:
          "authorized-relationship-commands-other-#{System.unique_integer([:positive])}",
        owner_email: context.bootstrap.principal.email
      )

    privileged_session =
      OfficeGraph.SessionCaseHelpers.create_session_with_capabilities!(
        context.bootstrap,
        [
          "graph_relationship.create",
          "graph_relationship.cross_workspace",
          "skeleton.read"
        ],
        prefix: "cross-workspace-relationship"
      )

    {:ok, operation} =
      Operations.start_operation(privileged_session, :graph_relationship_create)

    other_workspace_item =
      insert_graph_item!(other_scope, "task", "Authorized cross-workspace command task")

    request =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: context.task_item.id,
        target_item_id: other_workspace_item.id,
        workspace_id: privileged_session.workspace_id
      })

    assert {:ok, relationship} =
             WorkGraph.create_relationship(privileged_session, operation, request)

    assert relationship.workspace_id == privileged_session.workspace_id
    assert relationship.target_item_id == other_workspace_item.id

    assert {:ok, [view]} =
             WorkGraph.list_relationships(privileged_session, context.task_item.id,
               direction: :outgoing,
               definition_keys: ["depends_on"]
             )

    assert view.governing_workspace_id == privileged_session.workspace_id
    assert view.source.visibility == :visible
    assert view.target == %{visibility: :redacted}
  end

  test "an active edge cannot replay under a different governing workspace", context do
    ensure_cross_workspace_capability!()
    other_scope = bootstrap_other_workspace!(context, "Governing Scope")
    remote_item = insert_graph_item!(other_scope, "task", "Remote governing-scope task")

    local_session =
      OfficeGraph.SessionCaseHelpers.create_session_with_capabilities!(
        context.bootstrap,
        ["graph_relationship.create", "graph_relationship.cross_workspace"],
        prefix: "local-governing-scope"
      )

    remote_session =
      OfficeGraph.SessionCaseHelpers.create_session_with_capabilities!(
        other_scope,
        ["graph_relationship.create", "graph_relationship.cross_workspace"],
        prefix: "remote-governing-scope"
      )

    {:ok, local_operation} =
      Operations.start_operation(local_session, :graph_relationship_create)

    {:ok, remote_operation} =
      Operations.start_operation(remote_session, :graph_relationship_create)

    local_request =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: context.task_item.id,
        target_item_id: remote_item.id,
        workspace_id: local_session.workspace_id
      })

    assert {:ok, relationship} =
             WorkGraph.create_relationship(local_session, local_operation, local_request)

    remote_request = %{local_request | workspace_id: remote_session.workspace_id}

    assert {:error, {:relationship_governing_scope_conflict, :workspace_id}} =
             WorkGraph.create_relationship(remote_session, remote_operation, remote_request)

    persisted = Ash.get!(GraphRelationship, relationship.id, authorize?: false)
    assert persisted.workspace_id == local_session.workspace_id
    assert persisted.operation_id == local_operation.id
  end

  test "cycle-permitting definitions accept reciprocal compatible edges", context do
    artifact_item = insert_graph_item!(context.bootstrap, "artifact", "Cycle-safe artifact")

    evidence_item =
      insert_graph_item!(context.bootstrap, "evidence_item", "Cycle-safe evidence")

    artifact_from_evidence =
      RelationshipRequest.new!(%{
        definition_key: "generated_from",
        source_item_id: artifact_item.id,
        target_item_id: evidence_item.id,
        workspace_id: context.session.workspace_id
      })

    evidence_from_artifact = %{
      artifact_from_evidence
      | source_item_id: evidence_item.id,
        target_item_id: artifact_item.id
    }

    assert {:ok, first} =
             WorkGraph.create_relationship(
               context.session,
               context.operation,
               artifact_from_evidence
             )

    assert {:ok, second} =
             WorkGraph.create_relationship(
               context.session,
               context.operation,
               evidence_from_artifact
             )

    assert first.source_item_id == second.target_item_id
    assert first.target_item_id == second.source_item_id
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
               %{valid_until: nil}
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

  test "supersede authorizes both the existing and replacement edge scopes", context do
    ensure_cross_workspace_capability!()
    other_scope = bootstrap_other_workspace!(context, "Supersede Scope")
    remote_item = insert_graph_item!(other_scope, "task", "Remote superseded endpoint")

    privileged_session =
      OfficeGraph.SessionCaseHelpers.create_session_with_capabilities!(
        context.bootstrap,
        ["graph_relationship.create", "graph_relationship.cross_workspace"],
        prefix: "cross-workspace-original"
      )

    {:ok, create_operation} =
      Operations.start_operation(privileged_session, :graph_relationship_create)

    original_request =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: context.task_item.id,
        target_item_id: remote_item.id,
        workspace_id: privileged_session.workspace_id
      })

    assert {:ok, original} =
             WorkGraph.create_relationship(
               privileged_session,
               create_operation,
               original_request
             )

    limited_session =
      OfficeGraph.SessionCaseHelpers.create_session_with_capabilities!(
        context.bootstrap,
        ["graph_relationship.supersede"],
        prefix: "local-only-supersede"
      )

    {:ok, supersede_operation} =
      Operations.start_operation(limited_session, :graph_relationship_supersede)

    local_replacement = %{
      original_request
      | target_item_id: context.other_task_item.id,
        workspace_id: limited_session.workspace_id
    }

    assert {:error, :forbidden} =
             WorkGraph.supersede_relationship(
               limited_session,
               supersede_operation,
               original,
               local_replacement
             )

    assert Ash.get!(GraphRelationship, original.id, authorize?: false).lifecycle == "active"
  end

  test "supersede rejects an already-active replacement without changing either edge", context do
    third_task_item = insert_graph_item!(context.bootstrap, "task", "Existing replacement task")

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

    assert {:ok, existing_replacement} =
             WorkGraph.create_relationship(
               context.session,
               context.operation,
               replacement_request
             )

    {:ok, supersede_operation} =
      Operations.start_operation(context.session, :graph_relationship_supersede)

    assert {:error, _error} =
             WorkGraph.supersede_relationship(
               context.session,
               supersede_operation,
               original,
               replacement_request
             )

    assert Ash.get!(GraphRelationship, original.id, authorize?: false).lifecycle == "active"

    persisted_replacement =
      Ash.get!(GraphRelationship, existing_replacement.id, authorize?: false)

    assert persisted_replacement.lifecycle == "active"
    assert is_nil(persisted_replacement.supersedes_relationship_id)
    assert persisted_replacement.operation_id == context.operation.id
  end

  test "relationship provenance must exist in the governing relationship scope", context do
    other_scope = bootstrap_other_workspace!(context, "Provenance")

    {:ok, intake_operation} =
      Operations.start_operation(other_scope.session, :manual_intake_submit)

    assert {:ok, intake} =
             Integrations.submit_manual_intake(other_scope.session, intake_operation, %{
               source_identity: "manual:relationship-provenance",
               replay_identity: "paste:#{System.unique_integer([:positive])}",
               body: "Remote relationship provenance input."
             })

    {:ok, verification_check} = create_required_verification_check(other_scope.session)
    {:ok, run_result} = create_ready_run(other_scope.session, verification_check)

    base_request = %{
      definition_key: "depends_on",
      source_item_id: context.task_item.id,
      target_item_id: context.other_task_item.id,
      workspace_id: context.session.workspace_id
    }

    for {field, id} <- [
          run_id: run_result.run.id,
          integration_event_id: intake.normalized_event.id
        ] do
      request = base_request |> Map.put(field, id) |> RelationshipRequest.new!()

      assert {:error, :forbidden} =
               WorkGraph.create_relationship(context.session, context.operation, request)
    end

    remote_source = insert_graph_item!(other_scope, "task", "Scoped provenance source")
    remote_target = insert_graph_item!(other_scope, "task", "Scoped provenance target")

    {:ok, remote_operation} =
      Operations.start_operation(other_scope.session, :graph_relationship_create)

    scoped_request =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: remote_source.id,
        target_item_id: remote_target.id,
        workspace_id: other_scope.session.workspace_id,
        run_id: run_result.run.id,
        integration_event_id: intake.normalized_event.id
      })

    assert {:ok, scoped_relationship} =
             WorkGraph.create_relationship(
               other_scope.session,
               remote_operation,
               scoped_request
             )

    assert scoped_relationship.run_id == run_result.run.id
    assert scoped_relationship.integration_event_id == intake.normalized_event.id
  end

  test "lifecycle commands authorize the locked relationship instead of caller fields", context do
    other_scope = bootstrap_other_workspace!(context, "Lifecycle")
    source = insert_graph_item!(other_scope, "task", "Remote lifecycle source")
    target = insert_graph_item!(other_scope, "task", "Remote lifecycle target")

    {:ok, remote_create_operation} =
      Operations.start_operation(other_scope.session, :graph_relationship_create)

    remote_request =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: source.id,
        target_item_id: target.id,
        workspace_id: other_scope.session.workspace_id
      })

    assert {:ok, remote_relationship} =
             WorkGraph.create_relationship(
               other_scope.session,
               remote_create_operation,
               remote_request
             )

    forged = forge_local_relationship(remote_relationship, context)

    {:ok, local_archive_operation} =
      Operations.start_operation(context.session, :graph_relationship_archive)

    assert {:error, :forbidden} =
             WorkGraph.archive_relationship(
               context.session,
               local_archive_operation,
               forged,
               %{}
             )

    assert Ash.get!(GraphRelationship, remote_relationship.id, authorize?: false).lifecycle ==
             "active"

    {:ok, remote_archive_operation} =
      Operations.start_operation(other_scope.session, :graph_relationship_archive)

    assert {:ok, archived} =
             WorkGraph.archive_relationship(
               other_scope.session,
               remote_archive_operation,
               remote_relationship,
               %{}
             )

    {:ok, local_restore_operation} =
      Operations.start_operation(context.session, :graph_relationship_restore)

    assert {:error, :forbidden} =
             WorkGraph.restore_relationship(
               context.session,
               local_restore_operation,
               forge_local_relationship(archived, context),
               %{}
             )

    assert Ash.get!(GraphRelationship, archived.id, authorize?: false).lifecycle == "archived"

    {:ok, remote_restore_operation} =
      Operations.start_operation(other_scope.session, :graph_relationship_restore)

    assert {:ok, restored} =
             WorkGraph.restore_relationship(
               other_scope.session,
               remote_restore_operation,
               archived,
               %{}
             )

    {:ok, local_supersede_operation} =
      Operations.start_operation(context.session, :graph_relationship_supersede)

    local_replacement =
      RelationshipRequest.new!(%{
        definition_key: "depends_on",
        source_item_id: context.task_item.id,
        target_item_id: context.other_task_item.id,
        workspace_id: context.session.workspace_id
      })

    assert {:error, :forbidden} =
             WorkGraph.supersede_relationship(
               context.session,
               local_supersede_operation,
               forge_local_relationship(restored, context),
               local_replacement
             )

    assert Ash.get!(GraphRelationship, restored.id, authorize?: false).lifecycle == "active"
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

  defp bootstrap_other_workspace!(context, label) do
    suffix = System.unique_integer([:positive])

    {:ok, scope} =
      Foundation.bootstrap_local_owner(
        organization_name: context.bootstrap.organization.name,
        organization_slug: context.bootstrap.organization.slug,
        workspace_name: "Relationship Commands #{label} Workspace #{suffix}",
        workspace_slug: "relationship-commands-#{String.downcase(label)}-#{suffix}",
        initiative_name: "Relationship Commands #{label} Initiative #{suffix}",
        initiative_slug: "relationship-commands-#{String.downcase(label)}-#{suffix}",
        owner_email: context.bootstrap.principal.email
      )

    scope
  end

  defp forge_local_relationship(relationship, context) do
    %{
      relationship
      | organization_id: context.session.organization_id,
        workspace_id: context.session.workspace_id,
        source_item_id: context.task_item.id,
        target_item_id: context.other_task_item.id
    }
  end

  defp ensure_cross_workspace_capability! do
    Ash.create!(
      Capability,
      %{
        id: Ecto.UUID.generate(),
        key: "graph_relationship.cross_workspace",
        description: "Authorize relationships with an endpoint outside the governing workspace."
      },
      action: :create,
      authorize?: false
    )
  end
end
