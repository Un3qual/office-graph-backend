defmodule OfficeGraph.NodeConversations.CommandsAndProjectionTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{NodeConversations, Operations, Repo, SessionCaseHelpers}
  alias OfficeGraph.AgentRuntime.{ExecutionWorker, ModelOutput, OutputRouter}
  alias OfficeGraph.NodeConversations.ConversationMessage
  alias OfficeGraph.TestSupport.AgentRuntimeSupport
  alias OfficeGraph.TestSupport.OperatorProjectionSupport

  test "opens one run-scoped conversation and replays the originating command" do
    context = AgentRuntimeSupport.invocation_fixture()
    attrs = conversation_attrs(context)
    operation = command!(context.session, :conversation_start, "conversation-start", attrs)

    assert {:ok, conversation} =
             NodeConversations.start(context.session, operation, attrs)

    assert conversation.organization_id == context.bootstrap.organization.id
    assert conversation.workspace_id == context.bootstrap.workspace.id
    assert conversation.run_id == context.run.id
    assert conversation.graph_item_id == context.graph_item_id
    assert conversation.created_by_principal_id == context.session.principal_id
    assert conversation.operation_id == operation.id
    assert conversation.purpose == "agent_runtime"
    assert conversation.visibility == "run_participants"

    assert {:ok, replay} = NodeConversations.start(context.session, operation, attrs)
    assert replay.id == conversation.id

    assert {:error, {:command_idempotency_conflict, operation_id}} =
             NodeConversations.start(
               context.session,
               operation,
               %{attrs | graph_item_id: Ecto.UUID.generate()}
             )

    assert operation_id == operation.id

    invalid_attrs = %{attrs | graph_item_id: Ecto.UUID.generate()}

    invalid_operation =
      command!(context.session, :conversation_start, "conversation-invalid-scope", invalid_attrs)

    assert {:error, :forbidden} =
             NodeConversations.start(context.session, invalid_operation, invalid_attrs)
  end

  test "requires conversation write authority independently from read authority" do
    context = AgentRuntimeSupport.invocation_fixture()

    read_only =
      SessionCaseHelpers.create_session_with_capabilities!(
        context.bootstrap,
        ["skeleton.read"],
        prefix: "conversation-read-only"
      )

    attrs = conversation_attrs(context)
    operation = command!(read_only, :conversation_start, "conversation-read-only", attrs)

    assert {:error, :forbidden} = NodeConversations.start(read_only, operation, attrs)
  end

  test "appends replay-safe human messages with explicit durable-action linkage" do
    context = AgentRuntimeSupport.invocation_fixture()
    conversation = start_conversation!(context)

    attrs = %{
      conversation_id: conversation.id,
      body: "Record the run start as the explicit domain action for this message.",
      contribution_kind: "domain_action",
      proposed_graph_change_id: nil,
      domain_action_operation_id: context.run.operation_id
    }

    operation = command!(context.session, :conversation_message_create, "human-message", attrs)

    assert {:ok, message} =
             NodeConversations.append_human_message(context.session, operation, attrs)

    assert message.conversation_id == conversation.id
    assert message.author_principal_id == context.session.principal_id
    assert message.operation_id == operation.id
    assert message.domain_action_operation_id == context.run.operation_id
    assert message.proposed_graph_change_id == nil
    assert message.source == "human"
    assert message.visibility == "run_participants"

    assert {:ok, replay} =
             NodeConversations.append_human_message(context.session, operation, attrs)

    assert replay.id == message.id
    assert Repo.aggregate(ConversationMessage, :count) == 1

    assert {:error, {:command_idempotency_conflict, operation_id}} =
             NodeConversations.append_human_message(
               context.session,
               operation,
               %{attrs | body: "A different body must not reuse the command operation."}
             )

    assert operation_id == operation.id

    invalid_attrs = %{
      attrs
      | contribution_kind: "comment",
        domain_action_operation_id: context.run.operation_id
    }

    invalid_operation =
      command!(
        context.session,
        :conversation_message_create,
        "hidden-domain-action",
        invalid_attrs
      )

    assert {:error, {:invalid_conversation_message_linkage, "comment"}} =
             NodeConversations.append_human_message(
               context.session,
               invalid_operation,
               invalid_attrs
             )

    missing_linkage_attrs = %{
      attrs
      | contribution_kind: "domain_action",
        domain_action_operation_id: nil
    }

    missing_linkage_operation =
      command!(
        context.session,
        :conversation_message_create,
        "missing-domain-action",
        missing_linkage_attrs
      )

    assert {:error, {:invalid_conversation_message_linkage, "domain_action"}} =
             NodeConversations.append_human_message(
               context.session,
               missing_linkage_operation,
               missing_linkage_attrs
             )
  end

  test "persists an explicit proposal linkage and rejects a proposal from another scope" do
    context = AgentRuntimeSupport.invocation_fixture()
    conversation = start_conversation!(context)
    proposal = proposal!(context)

    attrs = %{
      conversation_id: conversation.id,
      body: "This message explicitly links to the bounded proposal.",
      contribution_kind: "proposal",
      proposed_graph_change_id: proposal.id,
      domain_action_operation_id: nil
    }

    operation = command!(context.session, :conversation_message_create, "proposal-message", attrs)

    assert {:ok, message} =
             NodeConversations.append_human_message(context.session, operation, attrs)

    assert message.proposed_graph_change_id == proposal.id

    other_context = AgentRuntimeSupport.invocation_fixture()
    other_proposal = proposal!(other_context)

    foreign_attrs = %{attrs | proposed_graph_change_id: other_proposal.id}

    foreign_operation =
      command!(context.session, :conversation_message_create, "foreign-proposal", foreign_attrs)

    assert {:error, :forbidden} =
             NodeConversations.append_human_message(
               context.session,
               foreign_operation,
               foreign_attrs
             )
  end

  test "projects human and agent provenance while redacting unauthorized referenced context" do
    context = AgentRuntimeSupport.invocation_fixture()

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        requested_capabilities: ["agent.model.generate"]
      })

    [job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)
    {:ok, step_operation} = Operations.read_operation(job.args["operation_id"])

    assert {:ok, agent_message} =
             Repo.transaction(fn ->
               OutputRouter.route!(
                 step_operation,
                 invoked.execution,
                 invoked.context_package,
                 "model:review",
                 %ModelOutput{
                   classification: :message,
                   safe_summary: "Agent-authored run message",
                   structured_content: %{"message" => %{"body" => "Agent-authored run message"}}
                 }
               )
             end)

    conversation =
      Ash.get!(OfficeGraph.NodeConversations.Conversation, agent_message.conversation_id,
        authorize?: false
      )

    human_attrs = %{
      conversation_id: conversation.id,
      body: "Human-authored run message",
      contribution_kind: "comment",
      proposed_graph_change_id: nil,
      domain_action_operation_id: nil
    }

    human_operation =
      command!(
        context.session,
        :conversation_message_create,
        "projected-human-message",
        human_attrs
      )

    assert {:ok, _human_message} =
             NodeConversations.append_human_message(
               context.session,
               human_operation,
               human_attrs
             )

    assert {:ok, projection} =
             NodeConversations.project(
               context.session,
               context.run.id,
               context.graph_item_id
             )

    assert projection.conversation.id == conversation.id
    assert Enum.map(projection.messages, & &1.source) == ["agent", "human"]

    projected_agent = Enum.find(projection.messages, &(&1.source == "agent"))
    assert projected_agent.author_principal_id == context.agent_principal.id
    assert projected_agent.execution_id == invoked.execution.id
    assert projected_agent.context_package_id == invoked.context_package.id
    assert projected_agent.referenced_context.visibility == "visible"
    assert projected_agent.referenced_context.package_id == invoked.context_package.id
    assert projected_agent.referenced_context.entries != []

    assert [projected_execution] = projection.executions
    assert projected_execution.id == invoked.execution.id
    assert projected_execution.state == "queued"
    assert projected_execution.requested_outcome == invoked.execution.requested_outcome
    assert projection.approval_requests == []
    assert projection.context_expansion_requests == []

    other_context = AgentRuntimeSupport.invocation_fixture()
    other_invoked = AgentRuntimeSupport.invoke_human(other_context)

    Repo.query!(
      "UPDATE conversation_messages SET context_package_id = $1 WHERE id = $2",
      [Ecto.UUID.dump!(other_invoked.context_package.id), Ecto.UUID.dump!(agent_message.id)]
    )

    assert {:ok, redacted_projection} =
             NodeConversations.project(
               context.session,
               context.run.id,
               context.graph_item_id
             )

    projected_agent = Enum.find(redacted_projection.messages, &(&1.source == "agent"))
    assert projected_agent.referenced_context == %{visibility: "redacted"}
  end

  test "projects the exact pending approval needed by the focused operator surface" do
    original = Application.get_env(:office_graph, :deterministic_model_approval_required)
    Application.put_env(:office_graph, :deterministic_model_approval_required, true)

    on_exit(fn ->
      if is_nil(original),
        do: Application.delete_env(:office_graph, :deterministic_model_approval_required),
        else: Application.put_env(:office_graph, :deterministic_model_approval_required, original)
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)
    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    assert {:ok, projection} =
             NodeConversations.project(
               context.session,
               context.run.id,
               context.graph_item_id
             )

    assert [%{id: execution_id, state: "waiting_approval"}] = projection.executions
    assert execution_id == invoked.execution.id

    assert [request] = projection.approval_requests
    assert request.execution_id == invoked.execution.id
    assert request.step_key == "model:review"
    assert request.requested_action == "model.generate"
    assert request.state == "pending"
    assert request.version == 1
    assert is_binary(request.reason)
    assert is_binary(request.scope_type)
    assert is_binary(request.scope_id)
    assert %DateTime{} = request.expires_at
  end

  test "disables invocation when the selected run is terminal or its autonomy changed" do
    terminal_context = AgentRuntimeSupport.invocation_fixture()

    terminal_context.run
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{
      state: "failed",
      aggregate_state: "failed",
      execution_state: "failed"
    })
    |> Ash.update!(authorize?: false)

    assert_invocation_disabled(terminal_context)

    changed_authority_context = AgentRuntimeSupport.invocation_fixture()

    Repo.query!(
      "UPDATE work_packet_versions SET autonomy_posture = 'bounded_automatic', updated_at = now() WHERE id = $1",
      [Ecto.UUID.dump!(changed_authority_context.packet_version.id)]
    )

    assert_invocation_disabled(changed_authority_context)
  end

  defp start_conversation!(context) do
    attrs = conversation_attrs(context)
    operation = command!(context.session, :conversation_start, "start-helper", attrs)
    {:ok, conversation} = NodeConversations.start(context.session, operation, attrs)
    conversation
  end

  defp conversation_attrs(context) do
    %{run_id: context.run.id, graph_item_id: context.graph_item_id}
  end

  defp assert_invocation_disabled(context) do
    assert {:ok, projection} =
             NodeConversations.project(context.session, context.run.id, context.graph_item_id)

    assert %{state: "disabled"} =
             Enum.find(projection.command_affordances, &(&1.identity == "invoke_agent"))

    refute "invoke_agent" in projection.allowed_next_actions
  end

  defp command!(session, action, key, attrs) do
    {:ok, operation} =
      Operations.start_command(
        session,
        action,
        "#{key}-#{System.unique_integer([:positive])}",
        attrs
      )

    operation
  end

  defp proposal!(context) do
    {:ok, intake} =
      OperatorProjectionSupport.submit_manual_intake(
        context.session,
        "conversation-proposal-#{System.unique_integer([:positive])}"
      )

    Enum.find(intake.proposed_changes, &(&1.change_type == "create_task"))
  end
end
