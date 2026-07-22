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
  import Ecto.Query

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
    [job] = execution_jobs(invoked.execution.id)
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
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
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

  defp execution_jobs(execution_id) do
    Oban.Job
    |> where(
      [job],
      job.worker == ^inspect(ExecutionWorker) and
        fragment("?->>'execution_id'", job.args) == ^execution_id
    )
    |> Repo.all()
  end
end
