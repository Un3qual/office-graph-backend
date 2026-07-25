defmodule OfficeGraph.AgentRuntime.AutomaticRunReviewAcceptanceTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Repo}
  alias OfficeGraph.AgentRuntime.{AgentExecution, ExecutionWorker, ModelRequest, ToolRequest}
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Runs.Run
  alias OfficeGraph.TestSupport.AgentRuntimeSupport
  alias OfficeGraph.WorkGraph.GraphItem

  require Ash.Query

  test "automatic run review routes one governed output without mutating its run or graph item" do
    context = AgentRuntimeSupport.invocation_fixture()
    original_run = Ash.get!(Run, context.run.id, authorize?: false)
    original_graph_item = Ash.get!(GraphItem, context.graph_item_id, authorize?: false)
    original_graph_item_count = Repo.aggregate(GraphItem, :count)

    request =
      AgentRuntimeSupport.request(context, %{
        origin: "system_trigger",
        invocation_mode: "automatic",
        idempotency_key: "automatic-run-review-#{context.suffix}"
      })

    assert {:ok, operation} = AgentRuntimeSupport.system_operation(context, request)
    assert operation.operation_kind == "system"
    assert operation.action == "agent.runtime.execute"
    assert operation.subject_kind == "work_run"
    assert operation.subject_id == context.run.id

    assert {:ok, first} = AgentRuntime.invoke_system(operation, request)
    assert {:ok, invocation_replay} = AgentRuntime.invoke_system(operation, request)

    assert first.execution.origin == "system_trigger"
    assert first.execution.invocation_mode == "automatic"
    assert invocation_replay.execution.id == first.execution.id
    assert Repo.aggregate(AgentExecution, :count) == 1

    assert [%Oban.Job{} = job] = AgentRuntimeSupport.execution_jobs(first.execution.id)
    assert job.worker == inspect(ExecutionWorker)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    assert :ok = ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3})
    assert {:ok, completed_replay} = AgentRuntime.invoke_system(operation, request)
    assert completed_replay.execution.id == first.execution.id
    assert completed_replay.execution.state == "completed"

    assert [model_request] =
             ModelRequest
             |> Ash.Query.filter(execution_id == ^first.execution.id)
             |> Ash.read!(authorize?: false)

    assert model_request.state == "succeeded"
    assert model_request.output_classification == "proposal"

    assert [] =
             ToolRequest
             |> Ash.Query.filter(execution_id == ^first.execution.id)
             |> Ash.read!(authorize?: false)

    assert [proposal] =
             ProposedGraphChange
             |> Ash.Query.filter(execution_id == ^first.execution.id)
             |> Ash.read!(authorize?: false)

    assert proposal.status == "pending"
    assert proposal.change_type == "create_task"
    assert proposal.context_package_id == first.context_package.id
    assert proposal.step_key == "model:review"

    assert [%Oban.Job{id: job_id}] = AgentRuntimeSupport.execution_jobs(first.execution.id)
    assert job_id == job.id
    assert Repo.aggregate(AgentExecution, :count) == 1

    persisted_run = Ash.get!(Run, context.run.id, authorize?: false)
    persisted_graph_item = Ash.get!(GraphItem, context.graph_item_id, authorize?: false)

    assert persisted_run == original_run
    assert persisted_graph_item == original_graph_item
    assert Repo.aggregate(GraphItem, :count) == original_graph_item_count
  end
end
