defmodule OfficeGraph.AgentRuntime.ContextExpansionCommands do
  @moduledoc false

  alias OfficeGraph.{Audit, Authorization, CommandSupport, DurableDelivery, Operations, Revisions}

  alias OfficeGraph.AgentRuntime.{
    ActionSupport,
    AgentExecution,
    AuthoritySnapshot,
    ContextAssembler,
    ContextExpansionRequest,
    ContextExpansionResolutionResult,
    ContextPackage,
    ExecutionStateMachine,
    ExecutionWorker,
    StorageResult
  }

  require Ash.Query

  @operation_action "agent.context_expansion.resolve"
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
      {:error, error} -> ActionSupport.rollback(ContextExpansionRequest, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def resolve(session_context, operation, request_id, expected_version, decision, reason)
      when is_map(session_context) and is_map(operation) do
    attrs = %{
      context_expansion_request_id: request_id,
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
             :agent_context_expansion_resolve,
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
    with {:ok, request_id} <- Ecto.UUID.cast(attrs.context_expansion_request_id),
         version when is_integer(version) and version > 0 <- attrs.expected_version,
         decision when decision in @decisions <- attrs.decision,
         reason when is_binary(reason) and byte_size(reason) in 1..2_000 <-
           attrs.resolution_reason do
      {:ok, request_id, version, decision, reason}
    else
      _invalid -> {:error, {:invalid_field, :context_expansion_resolution}}
    end
  end

  defp persist_resolution(session_context, operation, request_id, version, decision, reason) do
    StorageResult.run(fn ->
      ContextExpansionRequest
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
         %ContextExpansionRequest{} = request <- lock_request(request_id, session_context),
         %AgentExecution{} = execution <-
           lock_execution(request.execution_id, session_context),
         %AuthoritySnapshot{} = snapshot <- lock_snapshot(request.authority_snapshot_id),
         %ContextPackage{} = package <- lock_package(request.current_context_package_id) do
      resources = %{
        request: request,
        execution: execution,
        snapshot: snapshot,
        package: package
      }

      resolve_locked(session_context, operation, resources, version, decision, reason)
    else
      nil -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_locked(
         session_context,
         operation,
         %{request: request, execution: execution, snapshot: snapshot, package: package},
         expected_version,
         decision,
         reason
       ) do
    cond do
      replay?(request, operation, expected_version, decision, reason) ->
        with {:ok, context_package} <- expanded_package(request.id) do
          {:ok, resolution_result(request, execution, context_package)}
        end

      request.version != expected_version ->
        {:error, {:stale_agent_context_expansion, request.id, request.version}}

      request.state != "pending" ->
        {:error, {:agent_context_expansion_resolved, request.id, request.state}}

      DateTime.compare(request.expires_at, DateTime.utc_now()) != :gt ->
        {:error, {:agent_context_expansion_expired, request.id}}

      not matching_wait?(request, execution, snapshot, package) ->
        {:error, {:stale_agent_context_expansion, request.id, request.version}}

      true ->
        persist_decision(
          session_context,
          operation,
          request,
          execution,
          snapshot,
          package,
          decision,
          reason
        )
    end
  end

  defp replay?(request, operation, expected_version, decision, reason) do
    request.resolution_operation_id == operation.id and request.version == expected_version + 1 and
      request.state == decision and request.resolution_reason == reason
  end

  defp matching_wait?(request, execution, snapshot, package) do
    request.execution_id == execution.id and request.authority_snapshot_id == snapshot.id and
      request.current_context_package_id == package.id and
      request.organization_id == execution.organization_id and
      request.workspace_id == execution.workspace_id and
      request.target_scope_type == "workspace" and
      request.target_scope_id == execution.workspace_id and
      request.step_key == execution.current_step_key and
      request.execution_state_version == execution.state_version and
      package.execution_id == execution.id and execution.state == "waiting_context"
  end

  defp persist_decision(
         session_context,
         operation,
         request,
         execution,
         snapshot,
         package,
         decision,
         reason
       ) do
    now = DateTime.utc_now()

    {next_state, failure_code} =
      if decision == "approved",
        do: {"queued", nil},
        else: {"cancelled", "context_expansion_#{decision}"}

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
         {:ok, context_package} <-
           persist_context_package(
             decision,
             execution,
             snapshot,
             operation,
             resolved,
             package
           ),
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
         :ok <- after_transition(decision, transitioned, resolved),
         :ok <- record_traces(session_context, operation, resolved, transitioned) do
      {:ok, resolution_result(resolved, transitioned, context_package)}
    end
  end

  defp persist_context_package(
         "approved",
         execution,
         snapshot,
         operation,
         resolved,
         package
       ) do
    {expanded, _entries} =
      ContextAssembler.persist_expansion!(execution, snapshot, operation, resolved, package)

    {:ok, expanded}
  end

  defp persist_context_package(
         _decision,
         _execution,
         _snapshot,
         _operation,
         _resolved,
         _package
       ),
       do: {:ok, nil}

  defp after_transition("approved", transitioned, resolved) do
    ExecutionWorker.enqueue_context_expansion_resume!(transitioned, resolved)
    :ok
  end

  defp after_transition(_decision, _transitioned, _resolved), do: :ok

  defp record_traces(session_context, operation, request, execution) do
    Audit.record_once!(
      operation,
      "agent_context_expansion.#{request.state}",
      "agent_context_expansion_request",
      request.id
    )

    Revisions.record_once!(
      operation,
      "agent_context_expansion_request",
      request.id,
      "agent_context_expansion.#{request.state}",
      "Agent context expansion #{request.state}"
    )

    Enum.reduce_while(
      [
        DurableDelivery.event_attrs(
          "agent-context-expansion-request:#{request.id}:v#{request.version}",
          "agent_context_expansion_request.#{request.state}",
          "agent_context_expansion_request",
          request.id,
          request.version
        ),
        DurableDelivery.event_attrs(
          "agent-execution:#{execution.id}:v#{execution.state_version}",
          "agent_execution.#{execution.state}",
          "agent_execution",
          execution.id,
          execution.state_version
        )
      ],
      :ok,
      fn attrs, :ok ->
        case DurableDelivery.record_and_enqueue(session_context, operation, attrs) do
          {:ok, _event} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end
    )
  end

  defp expanded_package(request_id) do
    ContextPackage
    |> Ash.Query.filter(expansion_request_id == ^request_id)
    |> Ash.read_one(authorize?: false)
  end

  defp resolution_result(request, execution, context_package) do
    ContextExpansionResolutionResult.build!(request, execution, context_package)
  end

  defp lock_request(request_id, session_context) do
    ContextExpansionRequest
    |> Ash.Query.filter(
      id == ^request_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> read_one()
  end

  defp lock_execution(execution_id, session_context) do
    AgentExecution
    |> Ash.Query.filter(
      id == ^execution_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.lock(:for_update)
    |> read_one()
  end

  defp lock_snapshot(snapshot_id) do
    AuthoritySnapshot
    |> Ash.Query.filter(id == ^snapshot_id)
    |> Ash.Query.lock(:for_update)
    |> read_one()
  end

  defp lock_package(package_id) do
    ContextPackage
    |> Ash.Query.filter(id == ^package_id)
    |> Ash.Query.lock(:for_update)
    |> read_one()
  end

  defp read_one(query) do
    case Ash.read_one(query, authorize?: false) do
      {:ok, record} -> record
      {:error, error} -> {:error, error}
    end
  end
end
