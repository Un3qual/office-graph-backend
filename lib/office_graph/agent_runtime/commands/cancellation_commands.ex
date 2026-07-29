defmodule OfficeGraph.AgentRuntime.CancellationCommands do
  @moduledoc false

  alias OfficeGraph.{Authorization, CommandSupport, DurableDelivery, Operations}
  alias OfficeGraph.DurableDelivery.DomainEvent

  alias OfficeGraph.AgentRuntime.{
    ActionSupport,
    AdapterRegistry,
    AgentExecution,
    ApprovalRequest,
    CancellationResult,
    ContextExpansionRequest,
    ExecutionStateMachine,
    ModelRequest,
    StorageResult
  }

  require Ash.Query

  @operation_action "agent.cancel"
  @failure_code "cancelled_by_operator"

  @behaviour Ash.Resource.Actions.Implementation

  @impl true
  def run(input, [mode: :persist_cancel], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    case persist_cancel_records(
           session_context,
           attrs.operation_id,
           attrs.execution_id,
           attrs.expected_state_version
         ) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(AgentExecution, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

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
      AgentExecution
      |> Ash.ActionInput.for_action(:persist_cancellation_contract, %{
        operation_id: operation.id,
        execution_id: execution_id,
        expected_state_version: expected_state_version
      })
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> ActionSupport.normalize_action_result()
    end)
  end

  defp persist_cancel_records(
         session_context,
         operation_id,
         execution_id,
         expected_state_version
       ) do
    with {:ok, operation} <- Operations.lock_operation(operation_id),
         {:ok, pending_gates} <- lock_pending_gates(execution_id, session_context),
         {:ok, %AgentExecution{} = execution} <-
           lock_execution(execution_id, session_context),
         {:ok, replayed?} <- cancellation_replay?(operation.id, execution.id) do
      cond do
        replayed? ->
          cancellation_result(execution, true)

        execution.state_version != expected_state_version ->
          {:error, {:stale_agent_execution, execution.id, execution.state_version}}

        ExecutionStateMachine.terminal?(execution.state) ->
          {:error, {:agent_execution_terminal, execution.id, execution.state}}

        true ->
          persist_cancellation(session_context, operation, execution, pending_gates)
      end
    else
      {:ok, nil} -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_cancellation(session_context, operation, execution, pending_gates) do
    now = DateTime.utc_now()

    with :ok <- ExecutionStateMachine.validate(execution.state, "cancelled"),
         {:ok, model_request} <-
           lock_active_model_request(execution.id, execution.current_step_key),
         :ok <- cancel_model_request(model_request, now),
         {:ok, cancelled_gate} <-
           cancel_pending_gate(session_context, operation, execution, pending_gates, now),
         {:ok, cancelled} <-
           execution
           |> Ash.Changeset.for_update(:transition, %{
             state: "cancelled",
             failure_code: @failure_code,
             lease_token: nil,
             lease_expires_at: nil,
             cancelled_at: now
           })
           |> Ash.update(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         :ok <- record_invalidation(session_context, operation, cancelled, cancelled_gate) do
      {:ok, CancellationResult.build!(cancelled, model_request, false)}
    end
  end

  defp lock_execution(execution_id, session_context) do
    AgentExecution
    |> Ash.Query.filter(
      id == ^execution_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp lock_pending_gates(execution_id, session_context) do
    with {:ok, approval} <-
           lock_pending_gate(
             ApprovalRequest,
             execution_id,
             session_context.organization_id,
             session_context.workspace_id
           ),
         {:ok, context_expansion} <-
           lock_pending_gate(
             ContextExpansionRequest,
             execution_id,
             session_context.organization_id,
             session_context.workspace_id
           ) do
      {:ok, %{approval: approval, context_expansion: context_expansion}}
    end
  end

  defp lock_pending_gate(resource, execution_id, organization_id, workspace_id) do
    resource
    |> Ash.Query.filter(
      execution_id == ^execution_id and organization_id == ^organization_id and
        workspace_id == ^workspace_id and state == "pending"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp lock_active_model_request(_execution_id, nil), do: {:ok, nil}

  defp lock_active_model_request(execution_id, step_key) do
    ModelRequest
    |> Ash.Query.filter(
      execution_id == ^execution_id and step_key == ^step_key and
        state in ["pending", "running", "retry_scheduled"]
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp lock_model_request(_execution_id, nil), do: {:ok, nil}

  defp lock_model_request(execution_id, step_key) do
    ModelRequest
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.sort(requested_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp cancellation_replay?(operation_id, execution_id) do
    DomainEvent
    |> Ash.Query.filter(
      operation_id == ^operation_id and event_kind == "agent_execution.cancelled" and
        subject_kind == "agent_execution" and subject_id == ^execution_id
    )
    |> Ash.Query.limit(1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, event} -> {:ok, is_struct(event, DomainEvent)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cancellation_result(execution, replayed?) do
    with {:ok, model_request} <-
           lock_model_request(execution.id, execution.current_step_key) do
      {:ok, CancellationResult.build!(execution, model_request, replayed?)}
    end
  end

  defp cancel_model_request(nil, _now), do: :ok

  defp cancel_model_request(request, now) do
    request
    |> Ash.Changeset.for_update(:record_result, %{
      state: "cancelled",
      failure_code: @failure_code,
      completed_at: now
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
    |> case do
      {:ok, _request} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cancel_pending_gate(
         session_context,
         operation,
         execution,
         pending_gates,
         now
       ) do
    candidate =
      case execution.state do
        "waiting_approval" -> {:approval, pending_gates.approval}
        "waiting_context" -> {:context_expansion, pending_gates.context_expansion}
        _active_state -> nil
      end

    case candidate do
      {kind, request} when not is_nil(request) ->
        if request.step_key == execution.current_step_key and
             request.execution_state_version == execution.state_version do
          request
          |> Ash.Changeset.for_update(:resolve, %{
            state: "cancelled",
            version: request.version + 1,
            resolution_operation_id: operation.id,
            resolved_by_principal_id: session_context.principal_id,
            resolution_reason: "execution_cancelled",
            resolved_at: now
          })
          |> Ash.update(authorize?: false, return_notifications?: true)
          |> CommandSupport.normalize_ash_write()
          |> case do
            {:ok, resolved} -> {:ok, {kind, resolved}}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, nil}
        end

      _missing_or_mismatched ->
        {:ok, nil}
    end
  end

  defp record_invalidation(session_context, operation, execution, cancelled_gate) do
    events = [
      DurableDelivery.event_attrs(
        "agent-execution:#{execution.id}:v#{execution.state_version}",
        "agent_execution.cancelled",
        "agent_execution",
        execution.id,
        execution.state_version
      )
      | gate_events(cancelled_gate)
    ]

    Enum.reduce_while(events, :ok, fn attrs, :ok ->
      case DurableDelivery.record_and_enqueue(session_context, operation, attrs) do
        {:ok, _event} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp gate_events(nil), do: []

  defp gate_events({:approval, request}) do
    [
      DurableDelivery.event_attrs(
        "agent-approval-request:#{request.id}:v#{request.version}",
        "agent_approval_request.cancelled",
        "agent_approval_request",
        request.id,
        request.version
      )
    ]
  end

  defp gate_events({:context_expansion, request}) do
    [
      DurableDelivery.event_attrs(
        "agent-context-expansion-request:#{request.id}:v#{request.version}",
        "agent_context_expansion_request.cancelled",
        "agent_context_expansion_request",
        request.id,
        request.version
      )
    ]
  end

  defp signal_active_adapter(%{model_request: nil}), do: :ok

  defp signal_active_adapter(%{model_request: request}) do
    with {:ok, adapter} <- AdapterRegistry.model(request.adapter_key, request.adapter_version) do
      adapter.cancel(request.id)
    else
      _unavailable -> :ok
    end
  catch
    _kind, _reason -> :ok
  end
end
