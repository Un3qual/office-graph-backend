defmodule OfficeGraphWeb.AgentGovernanceApiTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ApprovalRequest,
    ContextExpansionRequest,
    ExecutionWorker
  }

  alias OfficeGraph.Repo
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

    cancelled =
      conn
      |> post(~p"/api/v1/commands/cancel-agent-execution", %{
        idempotency_key: "json-cancel-agent-#{context.suffix}",
        execution_id: payload["execution"]["id"],
        expected_state_version: payload["execution"]["stateVersion"]
      })
      |> json_response(200)

    assert cancelled["command"] == "cancel_agent_execution"
    assert cancelled["result"]["execution"]["state"] == "cancelled"
    assert cancelled["result"]["execution"]["state_version"] == 2
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
      |> post(~p"/api/v1/commands/resolve-agent-context-expansion", input)
      |> json_response(200)

    assert first["command"] == "resolve_agent_context_expansion"
    assert first["result"]["request"]["state"] == "approved"
    assert first["result"]["request"]["version"] == 2
    assert first["result"]["execution"]["state"] == "queued"
    assert is_binary(first["result"]["context_package_id"])

    stale =
      conn
      |> post(
        ~p"/api/v1/commands/resolve-agent-context-expansion",
        %{input | idempotency_key: "json-context-expansion-stale-#{fixture.context.suffix}"}
      )

    assert stale.status == 409

    assert %{
             "command" => "resolve_agent_context_expansion",
             "error" => %{
               "code" => "stale_agent_context_expansion",
               "current_version" => 2
             }
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

    Repo.query!(
      "UPDATE agent_context_entries SET posture = 'expansion_required' WHERE id = $1",
      [Ecto.UUID.dump!(target.id)]
    )

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    request =
      ContextExpansionRequest
      |> Ash.Query.filter(execution_id == ^execution.id and state == "pending")
      |> Ash.read_one!(authorize?: false)

    %{context: context, execution: execution, request: request}
  end

  defp allow_generic_context_expansion!(context) do
    Repo.query!(
      """
      UPDATE agent_definitions
      SET requested_capabilities = ARRAY[
            'agent.model.generate',
            'agent.tool.read',
            'evidence.suggest',
            'proposal.create'
          ]::text[],
          updated_at = now()
      WHERE id = $1
      """,
      [Ecto.UUID.dump!(context.definition.id)]
    )

    Repo.query!(
      """
      INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
      SELECT gen_random_uuid(), assignments.role_id, capabilities.id, now(), now()
      FROM role_assignments AS assignments
      JOIN capabilities ON capabilities.key = 'agent.tool.read'
      WHERE assignments.principal_id IN ($1, $2)
        AND assignments.organization_id = $3
        AND assignments.workspace_id = $4
      ON CONFLICT (role_id, capability_id) DO NOTHING
      """,
      [
        Ecto.UUID.dump!(context.agent_principal.id),
        Ecto.UUID.dump!(context.bootstrap.principal.id),
        Ecto.UUID.dump!(context.bootstrap.organization.id),
        Ecto.UUID.dump!(context.bootstrap.workspace.id)
      ]
    )
  end
end
