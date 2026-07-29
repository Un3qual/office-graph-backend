defmodule OfficeGraph.AgentRuntime.GateExpiryResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:complete, :snooze]]

    field :delay_seconds, :integer, constraints: [min: 1]
  end

  def complete!, do: new!(status: :complete)
  def snooze!(delay_seconds), do: new!(status: :snooze, delay_seconds: delay_seconds)

  def to_oban_result(%__MODULE__{status: :complete}), do: :ok

  def to_oban_result(%__MODULE__{status: :snooze, delay_seconds: delay_seconds}),
    do: {:snooze, delay_seconds}
end

defmodule OfficeGraph.AgentRuntime.GateExpiryWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{CommandSupport, DurableDelivery, Operations}

  alias OfficeGraph.AgentRuntime.{
    ActionSupport,
    AgentExecution,
    ApprovalRequest,
    ContextExpansionRequest,
    ExecutionStateMachine,
    GateExpiryResult,
    StorageResult
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
  def timeout(_job), do: :timer.minutes(30)

  @behaviour Ash.Resource.Actions.Implementation

  @impl Ash.Resource.Actions.Implementation
  def run(input, [request_kind: request_kind], _context)
      when request_kind in ["approval", "context_expansion"] do
    resource = request_resource(request_kind)

    case expire_locked(request_kind, input.arguments.request_id) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(resource, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id, "request_kind" => request_kind}})
      when is_binary(request_id) and request_kind in ["approval", "context_expansion"] do
    expire(request_kind, request_id)
  end

  def perform(_job), do: {:cancel, "invalid_agent_gate_expiry_job"}

  defp expire(request_kind, request_id) do
    StorageResult.run(fn ->
      request_kind
      |> request_resource()
      |> Ash.ActionInput.for_action(:expire_gate_contract, %{request_id: request_id})
      |> Ash.run_action(authorize?: false)
      |> ActionSupport.normalize_action_result()
      |> case do
        {:ok, result} -> GateExpiryResult.to_oban_result(result)
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp expire_locked(request_kind, request_id) do
    with {:ok, request} <- lock_request(request_kind, request_id) do
      if is_nil(request) do
        {:ok, GateExpiryResult.complete!()}
      else
        with {:ok, execution} <- lock_execution(request.execution_id) do
          expire_request(request_kind, request, execution)
        end
      end
    end
  end

  defp expire_request(_request_kind, %{state: state}, _execution) when state != "pending",
    do: {:ok, GateExpiryResult.complete!()}

  defp expire_request(request_kind, request, execution) do
    now = DateTime.utc_now()

    cond do
      DateTime.compare(request.expires_at, now) == :gt ->
        {:ok, GateExpiryResult.snooze!(max(DateTime.diff(request.expires_at, now, :second), 1))}

      matching_wait?(request_kind, request, execution) ->
        with {:ok, operation} <- Operations.read_operation(request.operation_id),
             {:ok, _expired} <- mark_expired(request_kind, request, now),
             :ok <- fail_waiting_execution(request_kind, execution, operation, now) do
          {:ok, GateExpiryResult.complete!()}
        end

      true ->
        with {:ok, _superseded} <- mark_superseded(request, now) do
          {:ok, GateExpiryResult.complete!()}
        end
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

  defp mark_expired(request_kind, request, now) do
    request
    |> Ash.Changeset.for_update(:resolve, %{
      state: "expired",
      version: request.version + 1,
      resolution_reason: "#{request_kind}_expired",
      resolved_at: now
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
  end

  defp mark_superseded(request, now) do
    request
    |> Ash.Changeset.for_update(:resolve, %{
      state: "superseded",
      version: request.version + 1,
      resolution_reason: "execution_no_longer_waiting",
      resolved_at: now
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
  end

  defp fail_waiting_execution(request_kind, execution, operation, now) do
    with :ok <- ExecutionStateMachine.validate(execution.state, "failed"),
         {:ok, failed} <-
           execution
           |> Ash.Changeset.for_update(:transition, %{
             state: "failed",
             failure_code: "agent_#{request_kind}_expired",
             lease_token: nil,
             lease_expires_at: nil,
             completed_at: now
           })
           |> Ash.update(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write() do
      record_failure_event(operation, failed)
    end
  end

  defp record_failure_event(operation, execution) do
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
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_request("approval", request_id), do: lock(ApprovalRequest, request_id)

  defp lock_request("context_expansion", request_id),
    do: lock(ContextExpansionRequest, request_id)

  defp lock(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp lock_execution(execution_id), do: lock(AgentExecution, execution_id)

  defp request_resource("approval"), do: ApprovalRequest
  defp request_resource("context_expansion"), do: ContextExpansionRequest

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
