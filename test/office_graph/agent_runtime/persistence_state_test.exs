defmodule OfficeGraph.AgentRuntime.PersistenceStateTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Foundation, Operations}
  alias OfficeGraph.AgentRuntime.AgentExecution
  alias OfficeGraph.NodeConversations.Conversation
  alias OfficeGraph.TestSupport.OperatorProjectionSupport
  alias OfficeGraph.WorkGraph.GraphItem

  test "execution transitions reject stale writes and terminal restarts" do
    fixture = persistence_fixture!()

    assert {:ok, binding} =
             AgentRuntime.bind_run_review_agent(fixture.bootstrap.session, %{
               idempotency_key: "execution-state-binding"
             })

    assert {:ok, operation} =
             Operations.start_operation(fixture.bootstrap.session, :agent_definition_bind)

    execution =
      Ash.create!(
        AgentExecution,
        %{
          id: Ecto.UUID.generate(),
          definition_id: binding.definition.id,
          organization_binding_id: binding.binding.id,
          organization_id: fixture.bootstrap.organization.id,
          workspace_id: fixture.bootstrap.workspace.id,
          run_id: fixture.run.id,
          graph_item_id: fixture.graph_item.id,
          agent_principal_id: binding.principal.id,
          delegator_principal_id: fixture.bootstrap.principal.id,
          operation_id: operation.id,
          invocation_mode: "human",
          origin: "operator",
          requested_outcome:
            "Review the selected run, work packet, graph context, checks, and evidence.",
          autonomy_mode: "human_supervised",
          state: "queued",
          idempotency_key: "execution-state"
        },
        action: :create,
        authorize?: false
      )

    stale = execution

    running =
      execution
      |> Ash.Changeset.for_update(:transition, %{state: "running"})
      |> Ash.update!(authorize?: false)

    assert running.state_version == 2

    assert {:error, stale_error} =
             stale
             |> Ash.Changeset.for_update(:transition, %{state: "cancelled"})
             |> Ash.update(authorize?: false)

    assert Exception.message(stale_error) =~ "stale"

    completed =
      running
      |> Ash.Changeset.for_update(:transition, %{state: "completed"})
      |> Ash.update!(authorize?: false)

    assert {:error, terminal_error} =
             completed
             |> Ash.Changeset.for_update(:transition, %{state: "running"})
             |> Ash.update(authorize?: false)

    assert Exception.message(terminal_error) =~ "state"
  end

  test "conversation lifecycle transitions reject stale writes" do
    fixture = persistence_fixture!()

    conversation =
      Ash.create!(
        Conversation,
        %{
          id: Ecto.UUID.generate(),
          organization_id: fixture.bootstrap.organization.id,
          workspace_id: fixture.bootstrap.workspace.id,
          graph_item_id: fixture.graph_item.id,
          run_id: fixture.run.id,
          created_by_principal_id: fixture.bootstrap.principal.id,
          operation_id: fixture.operation.id,
          purpose: "run_review",
          visibility: "run_participants",
          state: "active"
        },
        action: :create,
        authorize?: false
      )

    stale = conversation

    closed =
      conversation
      |> Ash.Changeset.for_update(:set_lifecycle_state, %{state: "closed"})
      |> Ash.update!(authorize?: false)

    assert closed.state_version == 2

    assert {:error, stale_error} =
             stale
             |> Ash.Changeset.for_update(:set_lifecycle_state, %{state: "archived"})
             |> Ash.update(authorize?: false)

    assert Exception.message(stale_error) =~ "stale"
  end

  defp persistence_fixture! do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, verification_check} =
      OperatorProjectionSupport.create_required_verification_check(bootstrap.session)

    {:ok, run_result} =
      OperatorProjectionSupport.create_ready_run(bootstrap.session, verification_check)

    graph_item = Ash.get!(GraphItem, verification_check.graph_item_id, authorize?: false)

    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    %{bootstrap: bootstrap, graph_item: graph_item, run: run_result.run, operation: operation}
  end
end
