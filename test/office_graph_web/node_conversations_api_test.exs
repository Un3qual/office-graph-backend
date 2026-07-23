defmodule OfficeGraphWeb.NodeConversationsApiTest do
  use OfficeGraphWeb.ConnCase, async: false

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
            conversation { id }
            commandAffordances {
              identity state requiredFields
              inputDefaults { field value values }
              targetIds { type id }
            }
          }
        }
        """,
        variables: %{runId: context.run.id, graphItemId: context.graph_item_id}
      })
      |> json_response(200)

    assert read["errors"] in [nil, []]
    projection = read["data"]["operatorRunConversation"]
    assert projection["conversation"] == nil

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
            conversation { id runId graphItemId state }
            messages {
              id source body authorPrincipalId executionId contextPackageId
              proposedGraphChangeId domainActionOperationId insertedAt
              referencedContext { visibility packageId version entries { posture rationaleCode } }
            }
            executions {
              id bindingId state stateVersion currentStepKey attemptCount failureCode
              requestedOutcome invocationMode origin autonomyMode insertedAt updatedAt
            }
            approvalRequests { id executionId stepKey requestedAction state version expiresAt }
            contextExpansionRequests { id executionId stepKey targetResourceType state version expiresAt }
          }
        }
        """,
        variables: %{runId: context.run.id, graphItemId: context.graph_item_id}
      })
      |> json_response(200)

    assert read["errors"] in [nil, []]

    assert read["data"]["operatorRunConversation"]["conversation"]["id"] ==
             payload["conversation"]["id"]

    assert read["data"]["operatorRunConversation"]["messages"] == []
    assert read["data"]["operatorRunConversation"]["executions"] == []
    assert read["data"]["operatorRunConversation"]["approvalRequests"] == []
    assert read["data"]["operatorRunConversation"]["contextExpansionRequests"] == []

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
      |> post(~p"/api/v1/commands/start-run-conversation", %{
        idempotency_key: "json-conversation-#{context.suffix}",
        run_id: context.run.id,
        graph_item_id: context.graph_item_id
      })
      |> json_response(200)

    conversation_id = started["result"]["conversation"]["id"]

    appended =
      conn
      |> post(~p"/api/v1/commands/append-conversation-message", %{
        idempotency_key: "json-conversation-message-#{context.suffix}",
        conversation_id: conversation_id,
        body: "Link this message to the run-start command.",
        contribution_kind: "domain_action",
        domain_action_operation_id: context.run.operation_id
      })
      |> json_response(200)

    assert appended["command"] == "append_conversation_message"
    assert appended["result"]["message"]["source"] == "human"
    assert appended["result"]["message"]["domain_action_operation_id"] == context.run.operation_id

    read =
      conn
      |> get(~p"/api/v1/runs/#{context.run.id}/graph-items/#{context.graph_item_id}/conversation")
      |> json_response(200)

    assert read["data"]["conversation"]["id"] == conversation_id

    assert [message] = read["data"]["messages"]
    assert message["body"] == "Link this message to the run-start command."
    assert message["domain_action_operation_id"] == context.run.operation_id
  end
end
