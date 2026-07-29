defmodule OfficeGraph.AgentRuntime.ApprovalCommands do
  @moduledoc false

  alias OfficeGraph.{Audit, Authorization, CommandSupport, DurableDelivery, Operations, Revisions}

  alias OfficeGraph.AgentRuntime.{
    ActionSupport,
    AgentExecution,
    ApprovalRequest,
    ApprovalResolutionResult,
    ExecutionStateMachine,
    ExecutionWorker,
    ModelRequest,
    StorageResult
  }

  require Ash.Query

  @operation_action "agent.approval.resolve"
  @decisions ~w(approved denied cancelled)

  @behaviour Ash.Resource.Actions.Implementation

  @impl true
  def run(input, [mode: :persist_resolution], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    case persist_resolution_records(
           session_context,
           attrs.operation_id,
           attrs.request_id,
           attrs.expected_version,
           attrs.decision,
           attrs.resolution_reason
         ) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(ApprovalRequest, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def resolve(session_context, operation, request_id, expected_version, decision, reason)
      when is_map(session_context) and is_map(operation) do
    attrs = %{
      approval_request_id: request_id,
      expected_version: expected_version,
      decision: decision,
      resolution_reason: reason
    }

    with {:ok, request_id, expected_version, decision, reason} <- validate_attrs(attrs),
         :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @operation_action),
         :ok <- Operations.validate_command_replay(operation, attrs),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :agent_approval_resolve,
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id
           ) do
      persist_resolution(
        session_context,
        operation,
        request_id,
        expected_version,
        decision,
        reason
      )
    end
  end

  def resolve(_session_context, _operation, _request_id, _expected_version, _decision, _reason),
    do: {:error, :forbidden}

  defp validate_attrs(attrs) do
    with {:ok, request_id} <- Ecto.UUID.cast(attrs.approval_request_id),
         version when is_integer(version) and version > 0 <- attrs.expected_version,
         decision when decision in @decisions <- attrs.decision,
         reason when is_binary(reason) and byte_size(reason) in 1..2_000 <-
           attrs.resolution_reason do
      {:ok, request_id, version, decision, reason}
    else
      _invalid -> {:error, {:invalid_field, :approval_resolution}}
    end
  end

  defp persist_resolution(session_context, operation, request_id, version, decision, reason) do
    StorageResult.run(fn ->
      ApprovalRequest
      |> Ash.ActionInput.for_action(:persist_resolution_contract, %{
        operation_id: operation.id,
        request_id: request_id,
        expected_version: version,
        decision: decision,
        resolution_reason: reason
      })
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> ActionSupport.normalize_action_result()
    end)
  end

  defp persist_resolution_records(
         session_context,
         operation_id,
         request_id,
         version,
         decision,
         reason
       ) do
    with {:ok, operation} <- Operations.lock_operation(operation_id),
         %ApprovalRequest{} = request <- lock_request(request_id, session_context),
         %AgentExecution{} = execution <-
           lock_execution(request.execution_id, session_context) do
      resolve_locked(
        session_context,
        operation,
        request,
        execution,
        version,
        decision,
        reason
      )
    else
      nil -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_locked(
         session_context,
         operation,
         request,
         execution,
         expected_version,
         decision,
         reason
       ) do
    cond do
      replay?(request, operation, expected_version, decision, reason) ->
        {:ok, resolution_result(request, execution)}

      request.version != expected_version ->
        {:error, {:stale_agent_approval, request.id, request.version}}

      request.state != "pending" ->
        {:error, {:agent_approval_resolved, request.id, request.state}}

      DateTime.compare(request.expires_at, DateTime.utc_now()) != :gt ->
        {:error, {:agent_approval_expired, request.id}}

      not matching_wait?(request, execution) ->
        {:error, {:stale_agent_approval, request.id, request.version}}

      true ->
        persist_decision(session_context, operation, request, execution, decision, reason)
    end
  end

  defp replay?(request, operation, expected_version, decision, reason) do
    request.resolution_operation_id == operation.id and request.version == expected_version + 1 and
      request.state == decision and request.resolution_reason == reason
  end

  defp matching_wait?(request, execution) do
    request.execution_id == execution.id and
      request.organization_id == execution.organization_id and
      request.workspace_id == execution.workspace_id and
      request.scope_type == "workspace" and request.scope_id == execution.workspace_id and
      request.step_key == execution.current_step_key and
      request.execution_state_version == execution.state_version and
      execution.state == "waiting_approval"
  end

  defp persist_decision(session_context, operation, request, execution, decision, reason) do
    now = DateTime.utc_now()

    {next_state, failure_code} =
      if decision == "approved", do: {"queued", nil}, else: {"cancelled", "approval_#{decision}"}

    with :ok <- ExecutionStateMachine.validate(execution.state, next_state),
         {:ok, resolved} <-
           request
           |> Ash.Changeset.for_update(:resolve, %{
             state: decision,
             version: request.version + 1,
             resolution_operation_id: operation.id,
             resolved_by_principal_id: session_context.principal_id,
             resolution_reason: reason,
             resolved_at: now
           })
           |> Ash.update(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         {:ok, transitioned} <-
           execution
           |> Ash.Changeset.for_update(:transition, %{
             state: next_state,
             failure_code: failure_code,
             lease_token: nil,
             lease_expires_at: nil,
             cancelled_at: if(next_state == "cancelled", do: now, else: nil)
           })
           |> Ash.update(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         :ok <- after_transition(decision, execution, transitioned, resolved, failure_code, now),
         :ok <- record_traces(session_context, operation, resolved, transitioned) do
      {:ok, resolution_result(resolved, transitioned)}
    end
  end

  defp after_transition("approved", _execution, transitioned, resolved, _failure_code, _now) do
    ExecutionWorker.enqueue_approval_resume!(transitioned, resolved)
    :ok
  end

  defp after_transition(_decision, execution, _transitioned, _resolved, failure_code, now) do
    cancel_active_model_request(execution.id, execution.current_step_key, failure_code, now)
  end

  defp record_traces(session_context, operation, request, execution) do
    Audit.record_once!(
      operation,
      "agent_approval.#{request.state}",
      "agent_approval_request",
      request.id
    )

    Revisions.record_once!(
      operation,
      "agent_approval_request",
      request.id,
      "agent_approval.#{request.state}",
      "Agent approval #{request.state}"
    )

    Enum.reduce_while([request_event(request), execution_event(execution)], :ok, fn attrs, :ok ->
      case DurableDelivery.record_and_enqueue(session_context, operation, attrs) do
        {:ok, _event} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolution_result(request, execution) do
    ApprovalResolutionResult.build!(request, execution)
  end

  defp request_event(request) do
    DurableDelivery.event_attrs(
      "agent-approval-request:#{request.id}:v#{request.version}",
      "agent_approval_request.#{request.state}",
      "agent_approval_request",
      request.id,
      request.version
    )
  end

  defp execution_event(execution) do
    DurableDelivery.event_attrs(
      "agent-execution:#{execution.id}:v#{execution.state_version}",
      "agent_execution.#{execution.state}",
      "agent_execution",
      execution.id,
      execution.state_version
    )
  end

  defp cancel_active_model_request(execution_id, step_key, failure_code, now) do
    ModelRequest
    |> Ash.Query.filter(
      execution_id == ^execution_id and step_key == ^step_key and
        state in ["pending", "running", "retry_scheduled"]
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        :ok

      {:ok, model_request} ->
        model_request
        |> Ash.Changeset.for_update(:record_result, %{
          state: "cancelled",
          failure_code: failure_code,
          completed_at: now
        })
        |> Ash.update(authorize?: false, return_notifications?: true)
        |> CommandSupport.normalize_ash_write()
        |> case do
          {:ok, _request} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lock_request(request_id, session_context) do
    ApprovalRequest
    |> Ash.Query.filter(
      id == ^request_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, request} -> request
      {:error, error} -> {:error, error}
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
    |> case do
      {:ok, execution} -> execution
      {:error, error} -> {:error, error}
    end
  end
end
