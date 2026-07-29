defmodule OfficeGraphWeb.AgentGovernanceApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ApprovalRequest,
    ContextExpansionRequest,
    ExecutionWorker
  }

  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  require Ash.Query

  test "GraphQL invokes and JSON cancels the exact run-linked agent execution", %{conn: conn} do
    context = AgentRuntimeSupport.invocation_fixture()
    conn = Ash.PlugHelpers.set_actor(conn, context.session)

    invoked =
      conn
      |> post(~p"/graphql", %{
        query: """
        mutation Invoke($input: InvokeAgentInput!) {
          invokeAgent(input: $input) {
            command operationId affectedIds { type id } contextPackageId
            execution { id state stateVersion currentStepKey }
          }
        }
        """,
        variables: %{
          input: %{
            idempotencyKey: "graphql-invoke-agent-#{context.suffix}",
            bindingId: context.binding.id,
            graphItemId: context.graph_item_id,
            runId: context.run.id,
            requestedOutcome:
              "Review the selected run, work packet, graph context, checks, and evidence, then propose bounded follow-up work.",
            requestedCapabilities: [
              "agent.model.generate",
              "evidence.suggest",
              "proposal.create"
            ],
            autonomyMode: "human_supervised"
          }
        }
      })
      |> json_response(200)

    assert invoked["errors"] in [nil, []]
    payload = invoked["data"]["invokeAgent"]
    assert payload["command"] == "invoke_agent"
    assert payload["execution"]["state"] == "queued"
    assert is_binary(payload["contextPackageId"])

    raw_execution_id =
      payload["affectedIds"]
      |> Enum.find(&(&1["type"] == "agent_execution"))
      |> Map.fetch!("id")

    assert {:ok, %{type: :agent_execution, id: ^raw_execution_id}} =
             AshGraphql.Resource.decode_relay_id(payload["execution"]["id"])

    cancelled =
      conn
      |> generated_json_api()
      |> post(~p"/api/v1/commands/cancel-agent-execution", %{
        data: %{
          idempotency_key: "json-cancel-agent-#{context.suffix}",
          execution_id: raw_execution_id,
          expected_state_version: payload["execution"]["stateVersion"]
        }
      })
      |> json_response(201)

    assert cancelled["command"] == "cancel_agent_execution"
    assert cancelled["execution"]["state"] == "cancelled"
    assert cancelled["execution"]["state_version"] == 2
  end

  test "GraphQL resolves the exact durable approval and returns its queued execution", %{
    conn: conn
  } do
    original = Application.get_env(:office_graph, :deterministic_model_approval_required)
    Application.put_env(:office_graph, :deterministic_model_approval_required, true)

    on_exit(fn ->
      if is_nil(original),
        do: Application.delete_env(:office_graph, :deterministic_model_approval_required),
        else: Application.put_env(:office_graph, :deterministic_model_approval_required, original)
    end)

    fixture = waiting_approval_fixture()

    response =
      conn
      |> Ash.PlugHelpers.set_actor(fixture.context.session)
      |> post(~p"/graphql", %{
        query: """
        mutation Resolve($input: ResolveAgentApprovalInput!) {
          resolveAgentApproval(input: $input) {
            command operationId affectedIds { type id }
            request { id state version resolutionOperationId }
            execution { id state stateVersion currentStepKey }
          }
        }
        """,
        variables: %{
          input: %{
            idempotencyKey: "graphql-agent-approval-#{fixture.context.suffix}",
            approvalRequestId: fixture.request.id,
            expectedVersion: fixture.request.version,
            decision: "approved",
            resolutionReason: "Approve the exact bounded model step."
          }
        }
      })
      |> json_response(200)

    assert response["errors"] in [nil, []]
    payload = response["data"]["resolveAgentApproval"]
    assert payload["command"] == "resolve_agent_approval"
    assert payload["request"]["state"] == "approved"
    assert payload["request"]["version"] == 2
    assert payload["execution"]["state"] == "queued"
    assert payload["execution"]["currentStepKey"] == "model:review"
  end

  test "JSON resolves a bounded context expansion and reports stale conflicts", %{conn: conn} do
    fixture = waiting_context_fixture()
    conn = Ash.PlugHelpers.set_actor(conn, fixture.context.session)

    input = %{
      idempotency_key: "json-context-expansion-#{fixture.context.suffix}",
      context_expansion_request_id: fixture.request.id,
      expected_version: fixture.request.version,
      decision: "approved",
      resolution_reason: "Approve only the requested workspace reference."
    }

    first =
      conn
      |> generated_json_api()
      |> post(~p"/api/v1/commands/resolve-agent-context-expansion", %{data: input})
      |> json_response(201)

    assert first["command"] == "resolve_agent_context_expansion"
    assert first["request"]["state"] == "approved"
    assert first["request"]["version"] == 2
    assert first["execution"]["state"] == "queued"
    assert is_binary(first["context_package_id"])

    stale =
      conn
      |> generated_json_api()
      |> post(
        ~p"/api/v1/commands/resolve-agent-context-expansion",
        %{
          data: %{
            input
            | idempotency_key: "json-context-expansion-stale-#{fixture.context.suffix}"
          }
        }
      )

    assert stale.status == 409

    assert %{
             "errors" => [
               %{
                 "code" => "stale_agent_context_expansion",
                 "meta" => %{"current_version" => 2}
               }
             ]
           } = json_response(stale, 409)
  end

  defp waiting_approval_fixture do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)
    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    request =
      ApprovalRequest
      |> Ash.Query.filter(execution_id == ^execution.id and state == "pending")
      |> Ash.read_one!(authorize?: false)

    %{context: context, execution: execution, request: request}
  end

  defp waiting_context_fixture do
    context = AgentRuntimeSupport.invocation_fixture()
    allow_generic_context_expansion!(context)

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        requested_capabilities: [
          "agent.model.generate",
          "agent.tool.read",
          "evidence.suggest",
          "proposal.create"
        ]
      })

    [job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)
    target = Enum.min_by(invoked.context_entries, & &1.ordinal)

    Ash.Seed.update!(target, %{posture: "expansion_required"})

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    request =
      ContextExpansionRequest
      |> Ash.Query.filter(execution_id == ^execution.id and state == "pending")
      |> Ash.read_one!(authorize?: false)

    %{context: context, execution: execution, request: request}
  end

  defp allow_generic_context_expansion!(context) do
    AgentRuntimeSupport.configure_definition!(context.definition, %{
      requested_capabilities: [
        "agent.model.generate",
        "agent.tool.read",
        "evidence.suggest",
        "proposal.create"
      ]
    })

    AgentRuntimeSupport.grant_capabilities!(
      context,
      ["agent.tool.read"],
      [
        context.agent_principal.id,
        context.bootstrap.principal.id
      ]
    )
  end

  defp generated_json_api(conn) do
    conn
    |> put_req_header("accept", "application/vnd.api+json")
    |> put_req_header("content-type", "application/vnd.api+json")
  end
end
