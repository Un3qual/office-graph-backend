defmodule OfficeGraphWeb.NodeConversationsApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.{NodeConversations, Operations, Repo}

  alias OfficeGraph.AgentRuntime.{
    ApprovalRequest,
    ContextExpansionRequest
  }

  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  test "GraphQL exposes scoped start and invoke affordances before a conversation exists", %{
    conn: conn
  } do
    context = AgentRuntimeSupport.invocation_fixture()
    conn = Ash.PlugHelpers.set_actor(conn, context.session)

    read =
      conn
      |> post(~p"/graphql", %{
        query: """
        query RunConversation($runId: ID!, $graphItemId: ID!) {
          operatorRunConversation(runId: $runId, graphItemId: $graphItemId) {
            commandAffordances {
              identity state requiredFields
              inputDefaults { field value values }
              targetIds { type id }
            }
          }
          conversation: conversationForRunGraphItem(
            runId: $runId
            graphItemId: $graphItemId
          ) { id }
        }
        """,
        variables: %{
          runId: relay_id(:work_run, context.run.id),
          graphItemId: relay_id(:graph_item, context.graph_item_id)
        }
      })
      |> json_response(200)

    assert read["errors"] in [nil, []]
    projection = read["data"]["operatorRunConversation"]
    assert read["data"]["conversation"] == nil

    start_affordance =
      Enum.find(projection["commandAffordances"], &(&1["identity"] == "start_run_conversation"))

    assert start_affordance["state"] == "enabled"
    assert start_affordance["requiredFields"] == ["run_id", "graph_item_id"]

    assert Enum.any?(
             start_affordance["inputDefaults"],
             &(&1["field"] == "run_id" and &1["value"] == context.run.id)
           )

    assert Enum.any?(
             start_affordance["inputDefaults"],
             &(&1["field"] == "graph_item_id" and &1["value"] == context.graph_item_id)
           )

    invoke_affordance =
      Enum.find(projection["commandAffordances"], &(&1["identity"] == "invoke_agent"))

    assert invoke_affordance["state"] == "enabled"

    assert Enum.any?(
             invoke_affordance["inputDefaults"],
             &(&1["field"] == "run_id" and &1["value"] == context.run.id)
           )

    assert Enum.any?(
             invoke_affordance["inputDefaults"],
             &(&1["field"] == "graph_item_id" and &1["value"] == context.graph_item_id)
           )
  end

  test "GraphQL opens and reads the focused run conversation", %{conn: conn} do
    context = AgentRuntimeSupport.invocation_fixture()
    conn = Ash.PlugHelpers.set_actor(conn, context.session)

    started =
      conn
      |> post(~p"/graphql", %{
        query: """
        mutation StartConversation($input: StartRunConversationInput!) {
          startRunConversation(input: $input) {
            command
            operationId
            affectedIds { type id }
            conversation {
              id runId graphItemId createdByPrincipalId operationId
              purpose visibility state stateVersion
            }
          }
        }
        """,
        variables: %{
          input: %{
            idempotencyKey: "graphql-conversation-#{context.suffix}",
            runId: context.run.id,
            graphItemId: context.graph_item_id
          }
        }
      })
      |> json_response(200)

    assert started["errors"] in [nil, []]
    payload = started["data"]["startRunConversation"]
    assert payload["command"] == "start_run_conversation"
    assert payload["conversation"]["runId"] == context.run.id
    assert payload["conversation"]["graphItemId"] == context.graph_item_id

    read =
      conn
      |> post(~p"/graphql", %{
        query: """
        query RunConversation($runId: ID!, $graphItemId: ID!) {
          operatorRunConversation(runId: $runId, graphItemId: $graphItemId) {
            type sourceWatermark
            allowedNextActions
            commandAffordances {
              identity state safeExplanation requiredFields
              inputDefaults { field value values }
              targetIds { type id }
            }
            messageContexts {
              messageId
              referencedContext { visibility packageId version entries { posture rationaleCode } }
            }
          }
          conversation: conversationForRunGraphItem(
            runId: $runId
            graphItemId: $graphItemId
          ) {
            id
            run { id }
            graphItem { id }
            state
            messages(first: 100) { edges { node { id } } }
            agentExecutions(first: 100) { edges { node { id } } }
          }
        }
        """,
        variables: %{
          runId: relay_id(:work_run, context.run.id),
          graphItemId: relay_id(:graph_item, context.graph_item_id)
        }
      })
      |> json_response(200)

    assert read["errors"] in [nil, []]

    assert read["data"]["conversation"]["id"] == payload["conversation"]["id"]
    assert read["data"]["conversation"]["run"]["id"] == relay_id(:work_run, context.run.id)

    assert read["data"]["conversation"]["graphItem"]["id"] ==
             relay_id(:graph_item, context.graph_item_id)

    assert read["data"]["conversation"]["messages"]["edges"] == []
    assert read["data"]["conversation"]["agentExecutions"]["edges"] == []
    assert read["data"]["operatorRunConversation"]["messageContexts"] == []

    assert "invoke_agent" in read["data"]["operatorRunConversation"]["allowedNextActions"]

    invoke_affordance =
      Enum.find(
        read["data"]["operatorRunConversation"]["commandAffordances"],
        &(&1["identity"] == "invoke_agent")
      )

    assert invoke_affordance["state"] == "enabled"
    assert Enum.any?(invoke_affordance["inputDefaults"], &(&1["field"] == "binding_id"))
  end

  test "JSON appends and reads a human message with explicit action provenance", %{conn: conn} do
    context = AgentRuntimeSupport.invocation_fixture()
    conn = Ash.PlugHelpers.set_actor(conn, context.session)

    started =
      conn
      |> generated_json_api()
      |> post(~p"/api/v1/commands/start-run-conversation", %{
        data: %{
          idempotency_key: "json-conversation-#{context.suffix}",
          run_id: context.run.id,
          graph_item_id: context.graph_item_id
        }
      })
      |> json_response(201)

    conversation_id = started["conversation"]["id"]

    appended =
      conn
      |> generated_json_api()
      |> post(~p"/api/v1/commands/append-conversation-message", %{
        data: %{
          idempotency_key: "json-conversation-message-#{context.suffix}",
          conversation_id: conversation_id,
          body: "Link this message to the run-start command.",
          contribution_kind: "domain_action",
          domain_action_operation_id: context.run.operation_id
        }
      })
      |> json_response(201)

    assert appended["command"] == "append_conversation_message"
    assert appended["message"]["source"] == "human"
    assert appended["message"]["domain_action_operation_id"] == context.run.operation_id

    read =
      conn
      |> get(~p"/api/v1/conversations/#{conversation_id}")
      |> json_response(200)

    assert read["data"]["id"] == conversation_id

    messages =
      conn
      |> get(~p"/api/v1/conversations/#{conversation_id}/messages")
      |> json_response(200)

    assert [message] = messages["data"]
    assert message["attributes"]["body"] == "Link this message to the run-start command."
    assert message["attributes"]["domain_action_operation_id"] == context.run.operation_id
  end

  test "generated conversation and agent resources use authorized Relay nodes and relationships",
       %{
         conn: conn
       } do
    context = AgentRuntimeSupport.invocation_fixture()
    conn = Ash.PlugHelpers.set_actor(conn, context.session)
    conversation = start_conversation!(context)
    message = append_message!(context, conversation)
    invoked = AgentRuntimeSupport.invoke_human(context)
    {approval, expansion} = create_gate_requests!(context, invoked)

    ids = %{
      run: relay_id(:work_run, context.run.id),
      graph_item: relay_id(:graph_item, context.graph_item_id),
      message: relay_id(:conversation_message, message.id),
      execution: relay_id(:agent_execution, invoked.execution.id),
      approval: relay_id(:agent_approval_request, approval.id),
      expansion: relay_id(:agent_context_expansion_request, expansion.id)
    }

    response =
      conn
      |> post(~p"/graphql", %{
        query: generated_conversation_query(),
        variables: %{
          runId: ids.run,
          graphItemId: ids.graph_item,
          messageId: ids.message,
          executionId: ids.execution,
          approvalId: ids.approval,
          expansionId: ids.expansion
        }
      })
      |> json_response(200)

    assert response["errors"] in [nil, []]
    data = response["data"]
    assert data["conversation"]["id"] == relay_id(:conversation, conversation.id)

    assert [message_node] = connection_nodes(data["conversation"]["messages"])
    assert message_node["id"] == ids.message

    assert [execution_node] = connection_nodes(data["conversation"]["agentExecutions"])
    assert execution_node["id"] == ids.execution
    assert [approval_node] = connection_nodes(execution_node["approvalRequests"])
    assert approval_node["id"] == ids.approval

    assert [expansion_node] = connection_nodes(execution_node["contextExpansionRequests"])
    assert expansion_node["id"] == ids.expansion

    assert data["message"]["id"] == ids.message
    assert data["execution"]["id"] == ids.execution
    assert data["approval"]["id"] == ids.approval
    assert data["expansion"]["id"] == ids.expansion

    Enum.each(
      [
        {"messageNode", ids.message},
        {"executionNode", ids.execution},
        {"approvalNode", ids.approval},
        {"expansionNode", ids.expansion}
      ],
      fn {field, id} -> assert data[field]["id"] == id end
    )
  end

  defp generated_conversation_query do
    """
    query GeneratedConversation(
      $runId: ID!
      $graphItemId: ID!
      $messageId: ID!
      $executionId: ID!
      $approvalId: ID!
      $expansionId: ID!
    ) {
      conversation: conversationForRunGraphItem(runId: $runId, graphItemId: $graphItemId) {
        id
        messages(first: 10) { edges { node { id } } }
        agentExecutions(first: 10) {
          edges {
            node {
              id
              approvalRequests(first: 10) { edges { node { id } } }
              contextExpansionRequests(first: 10) { edges { node { id } } }
            }
          }
        }
      }
      message: getConversationMessage(id: $messageId) { id }
      execution: getAgentExecution(id: $executionId) { id }
      approval: getAgentApprovalRequest(id: $approvalId) { id }
      expansion: getAgentContextExpansionRequest(id: $expansionId) { id }
      messageNode: node(id: $messageId) { id }
      executionNode: node(id: $executionId) { id }
      approvalNode: node(id: $approvalId) { id }
      expansionNode: node(id: $expansionId) { id }
    }
    """
  end

  defp start_conversation!(context) do
    attrs = %{run_id: context.run.id, graph_item_id: context.graph_item_id}

    {:ok, operation} =
      Operations.start_command(
        context.session,
        :conversation_start,
        "generated-conversation-#{context.suffix}",
        attrs
      )

    {:ok, conversation} = NodeConversations.start(context.session, operation, attrs)
    conversation
  end

  defp append_message!(context, conversation) do
    attrs = %{
      conversation_id: conversation.id,
      body: "Generated conversation resource message.",
      contribution_kind: "comment",
      proposed_graph_change_id: nil,
      domain_action_operation_id: nil
    }

    {:ok, operation} =
      Operations.start_command(
        context.session,
        :conversation_message_create,
        "generated-message-#{context.suffix}",
        attrs
      )

    {:ok, message} = NodeConversations.append_human_message(context.session, operation, attrs)
    message
  end

  defp create_gate_requests!(context, invoked) do
    expires_at = DateTime.add(DateTime.utc_now(), 3_600, :second)

    approval =
      Repo.ash_create!(ApprovalRequest, %{
        execution_id: invoked.execution.id,
        authority_snapshot_id: invoked.authority_snapshot.id,
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.bootstrap.workspace.id,
        operation_id: invoked.operation.id,
        step_key: "generated-approval",
        execution_state_version: invoked.execution.state_version,
        requested_action: "repository.read",
        reason: "Verify generated approval relationships.",
        scope_type: "workspace",
        scope_id: context.bootstrap.workspace.id,
        capability_key: "repository.read",
        sensitivity: "internal",
        state: "pending",
        expires_at: expires_at
      })

    expansion =
      Repo.ash_create!(ContextExpansionRequest, %{
        execution_id: invoked.execution.id,
        current_context_package_id: invoked.context_package.id,
        authority_snapshot_id: invoked.authority_snapshot.id,
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.bootstrap.workspace.id,
        operation_id: invoked.operation.id,
        step_key: "generated-expansion",
        execution_state_version: invoked.execution.state_version,
        target_resource_type: "repository",
        target_resource_id: context.graph_item_id,
        target_scope_type: "workspace",
        target_scope_id: context.bootstrap.workspace.id,
        access_mode: "read",
        capability_key: "repository.read",
        reason: "Verify generated expansion relationships.",
        sensitivity: "internal",
        expected_duration_seconds: 300,
        state: "pending",
        expires_at: expires_at
      })

    {approval, expansion}
  end

  defp connection_nodes(%{"edges" => edges}), do: Enum.map(edges, & &1["node"])

  defp relay_id(type, id) do
    Absinthe.Relay.Node.to_global_id(Atom.to_string(type), id, OfficeGraphWeb.GraphQL.Schema)
  end

  defp generated_json_api(conn) do
    conn
    |> put_req_header("accept", "application/vnd.api+json")
    |> put_req_header("content-type", "application/vnd.api+json")
  end
end
