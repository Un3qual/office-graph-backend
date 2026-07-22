defmodule OfficeGraph.Projections.OperatorRunAgentActivityTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Operations, Projections, Repo}
  alias OfficeGraph.AgentRuntime.{ExecutionWorker, ModelOutput, OutputRouter}
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  import Ecto.Query

  test "run activity includes bounded agent execution and conversation summaries" do
    context = AgentRuntimeSupport.invocation_fixture()

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        requested_capabilities: ["agent.model.generate"]
      })

    [job] = execution_jobs(invoked.execution.id)
    {:ok, step_operation} = Operations.read_operation(job.args["operation_id"])

    assert {:ok, message} =
             Repo.transaction(fn ->
               OutputRouter.route!(
                 step_operation,
                 invoked.execution,
                 invoked.context_package,
                 "model:review",
                 %ModelOutput{
                   classification: :message,
                   safe_summary: "Safe activity summary",
                   structured_content: %{"message" => %{"body" => "Safe activity summary"}}
                 }
               )
             end)

    assert {:ok, page} =
             Projections.operator_run_activity_page(context.session, context.run.id,
               limit: 100,
               after_cursor: nil
             )

    activities = Enum.map(page.edges, & &1.node)

    assert %{kind: "agent_execution", stable_id: execution_id, status: "queued"} =
             Enum.find(activities, &(&1.kind == "agent_execution"))

    assert execution_id == invoked.execution.id

    assert %{
             kind: "agent_context",
             stable_id: context_package_id,
             title: "Agent context version 1",
             status: "assembled"
           } = Enum.find(activities, &(&1.kind == "agent_context"))

    assert context_package_id == invoked.context_package.id

    assert %{
             kind: "conversation_message",
             stable_id: message_id,
             title: "Agent message",
             status: "recorded"
           } = Enum.find(activities, &(&1.kind == "conversation_message"))

    assert message_id == message.id
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
