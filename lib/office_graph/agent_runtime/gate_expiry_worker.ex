defmodule OfficeGraph.AgentRuntime.GateExpiryWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{DurableDelivery, Operations, Repo}

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ApprovalRequest,
    ContextExpansionRequest,
    ExecutionStateMachine
  }

  require Ash.Query

  def enqueue!(request)
      when is_struct(request, ApprovalRequest) or is_struct(request, ContextExpansionRequest) do
    request
    |> expiry_args()
    |> new(scheduled_at: request.expires_at)
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id, "request_kind" => request_kind}})
      when is_binary(request_id) and request_kind in ["approval", "context_expansion"] do
    expire(request_kind, request_id)
  end

  def perform(_job), do: {:cancel, "invalid_agent_gate_expiry_job"}

  defp expire(request_kind, request_id) do
    case Repo.transaction(fn -> expire_locked(request_kind, request_id) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp expire_locked(request_kind, request_id) do
    request = lock_request(request_kind, request_id)

    if is_nil(request) do
      :ok
    else
      execution = lock_execution(request.execution_id)
      expire_request(request_kind, request, execution)
    end
  end

  defp expire_request(_request_kind, %{state: state}, _execution) when state != "pending", do: :ok

  defp expire_request(request_kind, request, execution) do
    now = DateTime.utc_now()

    cond do
      DateTime.compare(request.expires_at, now) == :gt ->
        {:snooze, max(DateTime.diff(request.expires_at, now, :second), 1)}

      matching_wait?(request_kind, request, execution) ->
        operation = read_operation!(request.operation_id)
        mark_expired!(request_kind, request, now)
        fail_waiting_execution!(request_kind, execution, operation, now)
        :ok

      true ->
        mark_superseded!(request, now)
        :ok
    end
  end

  defp matching_wait?(_request_kind, _request, nil), do: false

  defp matching_wait?(request_kind, request, execution) do
    execution.state == waiting_state(request_kind) and
      execution.state_version == request.execution_state_version and
      execution.current_step_key == request.step_key and
      execution.organization_id == request.organization_id and
      execution.workspace_id == request.workspace_id
  end

  defp mark_expired!(request_kind, request, now) do
    request
    |> Ash.Changeset.for_update(:resolve, %{
      state: "expired",
      version: request.version + 1,
      resolution_reason: "#{request_kind}_expired",
      resolved_at: now
    })
    |> Repo.ash_update!()
  end

  defp mark_superseded!(request, now) do
    request
    |> Ash.Changeset.for_update(:resolve, %{
      state: "superseded",
      version: request.version + 1,
      resolution_reason: "execution_no_longer_waiting",
      resolved_at: now
    })
    |> Repo.ash_update!()
  end

  defp fail_waiting_execution!(request_kind, execution, operation, now) do
    with :ok <- ExecutionStateMachine.validate(execution.state, "failed") do
      failed =
        execution
        |> Ash.Changeset.for_update(:transition, %{
          state: "failed",
          failure_code: "agent_#{request_kind}_expired",
          lease_token: nil,
          lease_expires_at: nil,
          completed_at: now
        })
        |> Repo.ash_update!()

      record_failure_event!(operation, failed)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp record_failure_event!(operation, execution) do
    attrs =
      DurableDelivery.event_attrs(
        "agent-execution:#{execution.id}:v#{execution.state_version}",
        "agent_execution.failed",
        "agent_execution",
        execution.id,
        execution.state_version
      )

    case DurableDelivery.record_system_and_enqueue(operation, attrs) do
      {:ok, _event} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp read_operation!(operation_id) do
    case Operations.read_operation(operation_id) do
      {:ok, operation} -> operation
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_request("approval", request_id), do: lock(ApprovalRequest, request_id)

  defp lock_request("context_expansion", request_id),
    do: lock(ContextExpansionRequest, request_id)

  defp lock(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_execution(execution_id), do: lock(AgentExecution, execution_id)

  defp waiting_state("approval"), do: "waiting_approval"
  defp waiting_state("context_expansion"), do: "waiting_context"

  defp expiry_args(%ApprovalRequest{} = request), do: expiry_args("approval", request)

  defp expiry_args(%ContextExpansionRequest{} = request),
    do: expiry_args("context_expansion", request)

  defp expiry_args(request_kind, request) do
    %{
      request_kind: request_kind,
      request_id: request.id
    }
  end
end
