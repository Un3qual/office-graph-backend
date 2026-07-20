defmodule OfficeGraph.AgentRuntime.PersistenceStateTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Foundation, Operations, Repo}
  alias OfficeGraph.AgentRuntime.AgentExecution
  alias OfficeGraph.NodeConversations.Conversation
  alias OfficeGraph.Runs.Run
  alias OfficeGraph.WorkGraph.GraphItem
  alias OfficeGraph.WorkPackets.WorkPacket

  test "execution transitions reject stale writes and terminal restarts" do
    fixture = persistence_fixture!()

    assert {:ok, binding} =
             AgentRuntime.bind_openspec_review_agent(fixture.bootstrap.session, %{
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
          requested_outcome: "Review the selected OpenSpec change",
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
          purpose: "openspec_review",
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

    graph_item =
      Ash.create!(
        GraphItem,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          resource_type: "task",
          resource_id: Ecto.UUID.generate(),
          title: "Agent runtime persistence state"
        },
        action: :create,
        authorize?: false
      )

    work_packet =
      Ash.create!(
        WorkPacket,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          title: "Agent runtime persistence state"
        },
        action: :create,
        authorize?: false
      )

    run_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO runs (
        id,
        work_packet_id,
        organization_id,
        workspace_id,
        state,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'running', now(), now())
      """,
      Enum.map(
        [run_id, work_packet.id, bootstrap.organization.id, bootstrap.workspace.id],
        &Ecto.UUID.dump!/1
      )
    )

    run = Ash.get!(Run, run_id, authorize?: false)

    {:ok, operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    %{bootstrap: bootstrap, graph_item: graph_item, run: run, operation: operation}
  end
end
