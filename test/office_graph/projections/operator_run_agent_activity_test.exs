defmodule OfficeGraph.Projections.OperatorRunAgentActivityTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Operations, Projections, Repo}
  alias OfficeGraph.AgentRuntime.{ModelOutput, OutputRouter}
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  test "run activity includes bounded agent execution and conversation summaries" do
    context = AgentRuntimeSupport.invocation_fixture()

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        requested_capabilities: ["agent.model.generate"]
      })

    [job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)
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

  test "activity cursor remains stable when an execution state update changes updated_at" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)

    assert {:ok, first_page} =
             Projections.operator_run_activity_page(context.session, context.run.id,
               limit: 100,
               after_cursor: nil
             )

    execution_edge =
      Enum.find(first_page.edges, fn edge ->
        edge.node.kind == "agent_execution" and edge.node.stable_id == invoked.execution.id
      end)

    Repo.query!(
      "UPDATE agent_executions SET updated_at = now() + interval '1 hour' WHERE id = $1",
      [Ecto.UUID.dump!(invoked.execution.id)]
    )

    assert {:ok, next_page} =
             Projections.operator_run_activity_page(context.session, context.run.id,
               limit: 100,
               after_cursor: execution_edge.cursor
             )

    refute Enum.any?(next_page.edges, &(&1.node.stable_id == invoked.execution.id))
  end
end
