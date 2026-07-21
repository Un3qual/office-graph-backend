defmodule OfficeGraph.AgentRuntime.ContextPackageTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Foundation, Operations, Repo, SessionCaseHelpers, WorkGraph}
  alias OfficeGraph.AgentRuntime.{ContextEntry, ContextPackage}
  alias OfficeGraph.TestSupport.AgentRuntimeSupport
  alias OfficeGraph.WorkGraph.{GraphItem, RelationshipRequest}

  setup do
    {:ok, AgentRuntimeSupport.invocation_fixture()}
  end

  test "invocation assembles immutable authorized references with stable rationale", context do
    first = AgentRuntimeSupport.invoke_human(context)
    request = first.request

    assert {:ok, replay} = AgentRuntime.invoke(context.session, first.operation, request)

    assert replay.context_package.id == first.context_package.id
    assert replay.context_package.package_hash == first.context_package.package_hash
    assert replay.context_package.version == 1
    assert replay.context_package.execution_id == first.execution.id
    assert replay.context_package.authority_snapshot_id == first.authority_snapshot.id

    entries = first.context_entries
    assert Enum.map(entries, & &1.ordinal) == Enum.to_list(0..(length(entries) - 1))

    assert Enum.any?(entries, fn entry ->
             entry.entry_type == "selected_graph_item" and
               entry.resource_id == context.graph_item_id and entry.posture == "included" and
               entry.rationale_code == "selected_for_agent_invocation"
           end)

    assert Enum.any?(entries, fn entry ->
             entry.entry_type == "work_run" and entry.resource_id == context.run.id and
               entry.posture == "included" and entry.rationale_code == "governing_work_run"
           end)

    assert Enum.any?(entries, fn entry ->
             entry.entry_type == "verification_check" and
               entry.resource_id == context.verification_check.id and
               entry.rationale_code == "required_by_work_run"
           end)

    assert Enum.all?(entries, fn entry ->
             entry.operation_id == first.operation.id and is_binary(entry.content_hash)
           end)

    assert Repo.aggregate(ContextPackage, :count) == 1
    assert Repo.aggregate(ContextEntry, :count) == length(entries)
  end

  test "cross-workspace neighbors become restricted placeholders without target leakage",
       context do
    remote_title = "Restricted roadmap #{System.unique_integer([:positive])}"

    {:ok, other_scope} =
      Foundation.bootstrap_local_owner(
        organization_name: context.bootstrap.organization.name,
        organization_slug: context.bootstrap.organization.slug,
        workspace_name: "Restricted Agent Workspace #{context.suffix}",
        workspace_slug: "restricted-agent-workspace-#{context.suffix}",
        initiative_name: remote_title,
        initiative_slug: "restricted-agent-initiative-#{context.suffix}",
        owner_email: context.bootstrap.principal.email
      )

    remote_item =
      Ash.create!(
        GraphItem,
        %{
          id: Ecto.UUID.generate(),
          organization_id: other_scope.organization.id,
          workspace_id: other_scope.workspace.id,
          resource_type: "initiative",
          resource_id: other_scope.initiative.id,
          title: remote_title
        },
        action: :create,
        authorize?: false
      )

    privileged =
      SessionCaseHelpers.create_session_with_capabilities!(
        context.bootstrap,
        [
          "graph_relationship.create",
          "graph_relationship.cross_workspace",
          "skeleton.read"
        ],
        prefix: "agent-context-cross-workspace"
      )

    {:ok, relationship_operation} =
      Operations.start_operation(privileged, :graph_relationship_create)

    request =
      RelationshipRequest.new!(%{
        definition_key: "contained_in",
        source_item_id: context.graph_item_id,
        target_item_id: remote_item.id,
        workspace_id: privileged.workspace_id
      })

    assert {:ok, relationship} =
             WorkGraph.create_relationship(privileged, relationship_operation, request)

    invocation = AgentRuntimeSupport.invoke_human(context)

    assert restricted =
             Enum.find(invocation.context_entries, fn entry ->
               entry.posture == "restricted" and entry.resource_id == relationship.id
             end)

    assert restricted.entry_type == "related_graph_item"
    assert restricted.resource_type == "graph_relationship"
    assert restricted.rationale_code == "related_item_outside_workspace"
    refute restricted.resource_id == remote_item.id
    refute inspect(invocation.context_entries) =~ remote_title
    refute inspect(invocation.context_entries) =~ remote_item.id
  end

  test "foreign selected context fails closed without partial runtime records", context do
    suffix = System.unique_integer([:positive])

    {:ok, foreign} =
      Foundation.bootstrap_local_owner(
        organization_name: "Foreign Context #{suffix}",
        organization_slug: "foreign-context-#{suffix}",
        workspace_name: "Foreign Context Workspace #{suffix}",
        workspace_slug: "foreign-context-workspace-#{suffix}",
        initiative_name: "Foreign Context Initiative #{suffix}",
        initiative_slug: "foreign-context-initiative-#{suffix}",
        owner_email: "foreign-context-#{suffix}@office-graph.local"
      )

    foreign_item =
      Ash.create!(
        GraphItem,
        %{
          id: Ecto.UUID.generate(),
          organization_id: foreign.organization.id,
          workspace_id: foreign.workspace.id,
          resource_type: "initiative",
          resource_id: foreign.initiative.id,
          title: foreign.initiative.name
        },
        action: :create,
        authorize?: false
      )

    request =
      AgentRuntimeSupport.request(context, %{
        graph_item_id: foreign_item.id,
        idempotency_key: "foreign-context-#{suffix}"
      })

    assert {:ok, operation} = AgentRuntimeSupport.human_operation(context.session, request)
    assert {:error, :forbidden} = AgentRuntime.invoke(context.session, operation, request)
    assert Repo.aggregate(ContextPackage, :count) == 0
    assert Repo.aggregate(ContextEntry, :count) == 0
  end
end
