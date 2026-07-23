defmodule OfficeGraph.AgentRuntime.AutomaticWorkflowContext do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    AuthoritySnapshot,
    DurableStepExecutor,
    OperationReader
  }

  require Ash.Query

  def load(execution_id, operation_id, organization_id, workspace_id, step_key) do
    with {:ok, %AgentExecution{} = execution} <- execution(execution_id),
         true <-
           execution.organization_id == organization_id and
             execution.workspace_id == workspace_id and
             execution.invocation_mode == "automatic",
         {:ok, %AuthoritySnapshot{} = snapshot} <- snapshot(execution.id),
         {:ok, operation} <- operation_reader().read_operation(operation_id),
         :ok <-
           DurableStepExecutor.validate_step_operation(operation, execution, snapshot, step_key) do
      {:ok, %{execution: execution, operation: operation, snapshot: snapshot}}
    else
      false -> {:error, :forbidden}
      {:error, {:not_found, _resource, _id}} -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  defp execution(execution_id) do
    case Ash.get(AgentExecution, execution_id, authorize?: false, not_found_error?: false) do
      {:ok, %AgentExecution{} = execution} -> {:ok, execution}
      {:ok, nil} -> {:error, :forbidden}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp snapshot(execution_id) do
    AuthoritySnapshot
    |> Ash.Query.filter(execution_id == ^execution_id and version == 1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %AuthoritySnapshot{} = snapshot} -> {:ok, snapshot}
      {:ok, nil} -> {:error, :forbidden}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp operation_reader do
    Application.get_env(
      :office_graph,
      :agent_runtime_operation_reader,
      OperationReader
    )
  end
end
