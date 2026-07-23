defmodule OfficeGraph.AgentRuntime.AutomaticWorkflowRegistry do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{AgentDefinition, AgentExecution, AuthoritySnapshot}
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
      {:error, :automatic_workflow_not_registered} -> {:cancel, "invalid_agent_job"}
    end
  end

  defp fetch(definition_key) do
    case Map.fetch(@workflows, definition_key) do
      {:ok, workflow} -> {:ok, workflow}
      :error -> {:error, :automatic_workflow_not_registered}
    end
  end
end
