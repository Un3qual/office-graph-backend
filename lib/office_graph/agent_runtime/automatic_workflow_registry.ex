defmodule OfficeGraph.AgentRuntime.AutomaticWorkflowRegistry do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{
    AgentDefinition,
    AgentExecution,
    AutomaticWorkflowContext,
    AuthoritySnapshot,
    DurableStepExecutor
  }

  alias OfficeGraph.AgentRuntime.Agents.OpenSpecReviewWorkflow

  @workflows %{
    "openspec-review" => OpenSpecReviewWorkflow
  }

  def prepare_initial(
        %AgentDefinition{key: definition_key},
        %AgentExecution{} = execution,
        %AuthoritySnapshot{} = snapshot
      ) do
    with {:ok, workflow} <- fetch(definition_key) do
      workflow.prepare_initial(execution, snapshot)
    end
  end

  def perform(workflow_key, job) when is_binary(workflow_key) do
    case fetch(workflow_key) do
      {:ok, workflow} -> workflow.perform(job)
      {:error, :automatic_workflow_not_registered} -> fail_unregistered(job)
    end
  end

  defp fail_unregistered(
         %Oban.Job{
           args: %{
             "execution_id" => execution_id,
             "operation_id" => operation_id,
             "organization_id" => organization_id,
             "step_key" => step_key,
             "workspace_id" => workspace_id
           }
         } = job
       ) do
    case AutomaticWorkflowContext.load(
           execution_id,
           operation_id,
           organization_id,
           workspace_id,
           step_key
         ) do
      {:ok, context} ->
        DurableStepExecutor.fail_unclaimed(
          context,
          %{key: step_key},
          job,
          "automatic_workflow_not_registered"
        )

      {:error, :integration_storage_unavailable} ->
        {:snooze, 1}

      {:error, _untrusted_job} ->
        DurableStepExecutor.finish_terminal_job(job, "invalid_agent_job")
    end
  end

  defp fail_unregistered(job),
    do: DurableStepExecutor.finish_terminal_job(job, "invalid_agent_job")

  defp fetch(definition_key) do
    case Map.fetch(@workflows, definition_key) do
      {:ok, workflow} -> {:ok, workflow}
      :error -> {:error, :automatic_workflow_not_registered}
    end
  end
end
