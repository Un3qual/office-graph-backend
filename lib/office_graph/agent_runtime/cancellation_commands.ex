defmodule OfficeGraph.AgentRuntime.CancellationCommands do
  @moduledoc false

  alias OfficeGraph.{Authorization, DurableDelivery, Operations, Repo}
  alias OfficeGraph.DurableDelivery.DomainEvent

  alias OfficeGraph.AgentRuntime.{
    AdapterRegistry,
    AgentDefinition,
    AgentExecution,
    ExecutionStateMachine,
    ModelRequest,
    StorageResult
  }

  require Ash.Query

  @operation_action "agent.cancel"
  @failure_code "cancelled_by_operator"

  def cancel(session_context, operation, attrs)
      when is_map(session_context) and is_map(operation) and is_map(attrs) do
    with {:ok, execution_id, expected_state_version} <- validate_attrs(attrs),
         :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @operation_action),
         :ok <- Operations.validate_command_replay(operation, attrs),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :agent_cancel,
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id
           ),
         {:ok, result} <-
           persist_cancel(
             session_context,
             operation,
             execution_id,
             expected_state_version
           ) do
      signal_active_adapter(result)
      {:ok, result}
    end
  end

  def cancel(_session_context, _operation, _attrs), do: {:error, :forbidden}

  defp validate_attrs(attrs) do
    allowed = [:execution_id, :expected_state_version]

    with true <- Enum.all?(Map.keys(attrs), &(&1 in allowed)),
         {:ok, execution_id} <- Ecto.UUID.cast(Map.get(attrs, :execution_id)),
         expected when is_integer(expected) and expected > 0 <-
           Map.get(attrs, :expected_state_version) do
      {:ok, execution_id, expected}
    else
      _invalid -> {:error, {:invalid_field, :cancellation}}
    end
  end

  defp persist_cancel(session_context, operation, execution_id, expected_state_version) do
    StorageResult.run(fn ->
      Repo.transaction(fn ->
        execution = lock_execution(execution_id, session_context)

        cond do
          is_nil(execution) ->
            Repo.rollback(:forbidden)

          cancellation_replay?(operation.id, execution.id) ->
            cancellation_result(execution, true)

          execution.state_version != expected_state_version ->
            Repo.rollback({:stale_agent_execution, execution.id, execution.state_version})

          ExecutionStateMachine.terminal?(execution.state) ->
            Repo.rollback({:agent_execution_terminal, execution.id, execution.state})

          true ->
            with :ok <- ExecutionStateMachine.validate(execution.state, "cancelled") do
              model_request = lock_active_model_request(execution.id, execution.current_step_key)
              cancel_model_request!(model_request)

              cancelled =
                execution
                |> Ash.Changeset.for_update(:transition, %{
                  state: "cancelled",
                  failure_code: @failure_code,
                  lease_token: nil,
                  lease_expires_at: nil,
                  cancelled_at: DateTime.utc_now()
                })
                |> Repo.ash_update!()

              record_invalidation!(session_context, operation, cancelled)

              %{
                execution: cancelled,
                model_request: model_request,
                replayed?: false
              }
            else
              {:error, reason} -> Repo.rollback(reason)
            end
        end
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp lock_execution(execution_id, session_context) do
    AgentExecution
    |> Ash.Query.filter(
      id == ^execution_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_active_model_request(_execution_id, nil), do: nil

  defp lock_active_model_request(execution_id, step_key) do
    ModelRequest
    |> Ash.Query.filter(
      execution_id == ^execution_id and step_key == ^step_key and
        state in ["pending", "running", "retry_scheduled"]
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_model_request(_execution_id, nil), do: nil

  defp lock_model_request(execution_id, step_key) do
    ModelRequest
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.sort(requested_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp cancellation_replay?(operation_id, execution_id) do
    DomainEvent
    |> Ash.Query.filter(
      operation_id == ^operation_id and event_kind == "agent_execution.cancelled" and
        subject_kind == "agent_execution" and subject_id == ^execution_id
    )
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
    |> is_struct(DomainEvent)
  end

  defp cancellation_result(execution, replayed?) do
    %{
      execution: execution,
      model_request: lock_model_request(execution.id, execution.current_step_key),
      replayed?: replayed?
    }
  end

  defp cancel_model_request!(nil), do: :ok

  defp cancel_model_request!(request) do
    request
    |> Ash.Changeset.for_update(:record_result, %{
      state: "cancelled",
      failure_code: @failure_code,
      completed_at: DateTime.utc_now()
    })
    |> Repo.ash_update!()

    :ok
  end

  defp record_invalidation!(session_context, operation, execution) do
    case DurableDelivery.record_and_enqueue(session_context, operation, %{
           event_key: "agent-execution:#{execution.id}:v#{execution.state_version}",
           event_kind: "agent_execution.cancelled",
           subject_kind: "agent_execution",
           subject_id: execution.id,
           subject_version: execution.state_version
         }) do
      {:ok, _event} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp signal_active_adapter(%{model_request: nil}), do: :ok
  defp signal_active_adapter(%{replayed?: true}), do: :ok

  defp signal_active_adapter(%{execution: execution, model_request: request}) do
    with {:ok, %AgentDefinition{} = definition} <-
           Ash.get(AgentDefinition, execution.definition_id,
             authorize?: false,
             not_found_error?: false
           ),
         {:ok, adapter} <- AdapterRegistry.model(definition.model_adapter_key) do
      adapter.cancel(request.id)
    else
      _unavailable -> :ok
    end
  catch
    _kind, _reason -> :ok
  end
end
