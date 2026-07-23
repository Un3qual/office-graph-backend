defmodule OfficeGraph.AgentRuntime.InvocationCommands do
  @moduledoc false

  alias OfficeGraph.{Authorization, Operations, Repo}

  alias OfficeGraph.AgentRuntime.{
    AgentDefinition,
    AgentExecution,
    Authority,
    AuthoritySnapshot,
    ContextAssembler,
    ExecutionWorker,
    InvocationRequest,
    OrganizationBinding,
    StorageResult
  }

  require Ash.Query

  @human_action "agent.invoke"

  def invoke(session_context, operation, %InvocationRequest{} = request)
      when is_map(session_context) and is_map(operation) do
    with :ok <- validate_human_envelope(request),
         :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @human_action),
         :ok <-
           Operations.validate_command_replay(
             operation,
             InvocationRequest.command_input(request)
           ),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :agent_invoke,
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id
           ),
         :ok <-
           Authorization.authorize(
             session_context,
             :skeleton_read,
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id
           ),
         {:ok, binding, definition} <-
           scoped_binding(
             request.binding_id,
             session_context.organization_id,
             session_context.workspace_id
           ) do
      persist(operation, request, binding, definition, session_context.principal_id)
    end
  end

  def invoke(_session_context, _operation, _request), do: {:error, :forbidden}

  def invoke_system(operation, %InvocationRequest{} = request) when is_map(operation) do
    with :ok <- validate_system_envelope(operation, request),
         :ok <- Operations.validate_system_operation(operation, :agent_runtime_execute),
         :ok <- validate_operation_idempotency(operation, request),
         {:ok, binding, definition} <-
           scoped_binding(request.binding_id, operation.organization_id, operation.workspace_id),
         :ok <- validate_system_trigger(operation, request, binding) do
      persist(operation, request, binding, definition, nil)
    else
      {:error, _reason} = error -> error
    end
  end

  def invoke_system(_operation, _request), do: {:error, :forbidden}

  defp validate_human_envelope(request) do
    if request.origin == "operator" and request.invocation_mode == "human",
      do: :ok,
      else: {:error, :forbidden}
  end

  defp validate_system_envelope(operation, request) do
    valid? =
      request.origin == "system_trigger" and request.invocation_mode == "automatic" and
        operation.operation_kind == "system" and operation.workspace_id != nil and
        operation.subject_kind == "work_run" and operation.subject_id == request.run_id

    if valid?, do: :ok, else: {:error, :forbidden}
  end

  defp validate_operation_idempotency(operation, request) do
    if operation.idempotency_key == request.idempotency_key,
      do: :ok,
      else: {:error, :forbidden}
  end

  defp scoped_binding(binding_id, organization_id, workspace_id)
       when is_binary(binding_id) and is_binary(organization_id) and is_binary(workspace_id) do
    OrganizationBinding
    |> Ash.Query.filter(
      id == ^binding_id and organization_id == ^organization_id and
        workspace_id == ^workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %OrganizationBinding{} = binding} ->
        case Ash.get(AgentDefinition, binding.definition_id,
               authorize?: false,
               not_found_error?: false
             ) do
          {:ok, %AgentDefinition{} = definition} ->
            {:ok, binding, definition}

          {:ok, _missing_or_inactive} ->
            {:error, :forbidden}

          {:error, _storage_error} ->
            {:error, :integration_storage_unavailable}
        end

      {:ok, nil} ->
        {:error, :forbidden}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp scoped_binding(_binding_id, _organization_id, _workspace_id),
    do: {:error, :forbidden}

  defp validate_system_trigger(operation, request, binding) do
    valid? =
      binding.agent_principal_id == operation.principal_id and
        operation.authority_basis == "agent-binding:#{binding.id}" and
        operation.causation_key == "work-run:#{request.run_id}" and
        operation.idempotency_scope == "agent-runtime:#{binding.id}:#{request.run_id}"

    if valid?, do: :ok, else: {:error, :forbidden}
  end

  defp persist(operation, request, binding, definition, delegator_principal_id) do
    StorageResult.run(fn ->
      Repo.transaction(fn ->
        with {:ok, locked_operation} <- Operations.lock_operation(operation.id),
             :ok <- validate_locked_operation(locked_operation, operation),
             {:ok, locked_binding, locked_definition} <-
               lock_binding_and_definition(binding, definition) do
          lock_invocation_identity!(locked_binding.id, request.run_id, request.idempotency_key)

          case existing_execution(locked_operation, locked_binding, request) do
            {:ok, nil} ->
              with :ok <- validate_new_invocation_lifecycle(locked_binding, locked_definition),
                   {:ok, authority} <-
                     Authority.compute(locked_binding, locked_definition, request,
                       delegator_principal_id: delegator_principal_id,
                       operation_id: locked_operation.id
                     ) do
                create_invocation!(
                  locked_operation,
                  locked_binding,
                  locked_definition,
                  request,
                  authority,
                  delegator_principal_id
                )
              else
                {:error, reason} -> Repo.rollback(reason)
              end

            {:ok, execution} ->
              replay_invocation!(
                execution,
                locked_operation,
                locked_binding,
                locked_definition,
                request,
                delegator_principal_id
              )

            {:error, reason} ->
              Repo.rollback(reason)
          end
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> normalize_transaction_result()
    end)
  end

  defp validate_locked_operation(locked, expected) do
    fields = [
      :id,
      :operation_kind,
      :principal_id,
      :session_id,
      :organization_id,
      :workspace_id,
      :action,
      :idempotency_key,
      :authority_basis,
      :causation_key,
      :idempotency_scope,
      :subject_kind,
      :subject_id,
      :subject_version
    ]

    if Enum.all?(fields, &(Map.get(locked, &1) == Map.get(expected, &1))),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp lock_binding_and_definition(binding, definition) do
    with {:ok, %OrganizationBinding{} = locked_binding} <-
           lock_record(OrganizationBinding, binding.id),
         {:ok, %AgentDefinition{} = locked_definition} <-
           lock_record(AgentDefinition, definition.id),
         true <-
           locked_binding.definition_id == locked_definition.id and
             locked_binding.organization_id == binding.organization_id and
             locked_binding.workspace_id == binding.workspace_id and
             locked_binding.agent_principal_id == binding.agent_principal_id do
      {:ok, locked_binding, locked_definition}
    else
      false -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  defp validate_new_invocation_lifecycle(binding, definition) do
    if binding.lifecycle_state == "active" and definition.lifecycle_state == "active",
      do: :ok,
      else: {:error, :forbidden}
  end

  defp lock_record(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :forbidden}
      result -> result
    end
  end

  defp existing_execution(operation, binding, request) do
    case execution_by_operation(operation.id) do
      {:ok, %AgentExecution{} = execution} ->
        {:ok, execution}

      {:ok, nil} ->
        execution_by_invocation_identity(binding.id, request.run_id, request.idempotency_key)

      {:error, _reason} = error ->
        error
    end
  end

  defp execution_by_operation(operation_id) do
    AgentExecution
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp execution_by_invocation_identity(binding_id, run_id, idempotency_key) do
    AgentExecution
    |> Ash.Query.filter(
      organization_binding_id == ^binding_id and run_id == ^run_id and
        idempotency_key == ^idempotency_key
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp create_invocation!(
         operation,
         binding,
         definition,
         request,
         authority,
         delegator_principal_id
       ) do
    projected_entries =
      case ContextAssembler.project(authority, request.graph_item_id, request.run_id) do
        {:ok, entries} -> entries
        {:error, reason} -> Repo.rollback(reason)
      end

    execution =
      Repo.ash_create!(AgentExecution, %{
        id: Ecto.UUID.generate(),
        definition_id: definition.id,
        organization_binding_id: binding.id,
        organization_id: binding.organization_id,
        workspace_id: binding.workspace_id,
        run_id: request.run_id,
        graph_item_id: request.graph_item_id,
        agent_principal_id: binding.agent_principal_id,
        delegator_principal_id: delegator_principal_id,
        operation_id: operation.id,
        invocation_mode: request.invocation_mode,
        origin: request.origin,
        requested_outcome: request.requested_outcome,
        autonomy_mode: request.autonomy_mode,
        state: "queued",
        state_version: 1,
        attempt_count: 0,
        idempotency_key: request.idempotency_key
      })

    snapshot =
      authority
      |> Map.put(:id, Ecto.UUID.generate())
      |> Map.put(:execution_id, execution.id)
      |> then(&Repo.ash_create!(AuthoritySnapshot, &1))

    {context_package, context_entries} =
      ContextAssembler.persist_initial!(execution, snapshot, operation, projected_entries)

    case ExecutionWorker.prepare_initial(execution, snapshot, definition) do
      {:ok, _prepared_step} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end

    invocation_result(operation, execution, snapshot, context_package, context_entries)
  end

  defp replay_invocation!(
         execution,
         operation,
         binding,
         definition,
         request,
         delegator_principal_id
       ) do
    matching? =
      Enum.all?(
        [
          {:definition_id, definition.id},
          {:organization_binding_id, binding.id},
          {:organization_id, binding.organization_id},
          {:workspace_id, binding.workspace_id},
          {:run_id, request.run_id},
          {:graph_item_id, request.graph_item_id},
          {:agent_principal_id, binding.agent_principal_id},
          {:delegator_principal_id, delegator_principal_id},
          {:operation_id, operation.id},
          {:invocation_mode, request.invocation_mode},
          {:origin, request.origin},
          {:requested_outcome, request.requested_outcome},
          {:autonomy_mode, request.autonomy_mode},
          {:idempotency_key, request.idempotency_key}
        ],
        fn {field, expected} -> Map.get(execution, field) == expected end
      )

    if matching? do
      snapshot =
        AuthoritySnapshot
        |> Ash.Query.filter(execution_id == ^execution.id and version == 1)
        |> Ash.read_one!(authorize?: false)

      case ContextAssembler.load_initial(execution.id) do
        {:ok, {context_package, context_entries}} ->
          invocation_result(operation, execution, snapshot, context_package, context_entries)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    else
      Repo.rollback({:agent_invocation_idempotency_conflict, execution.id})
    end
  end

  defp invocation_result(operation, execution, snapshot, context_package, context_entries) do
    %{
      operation: operation,
      execution: execution,
      authority_snapshot: snapshot,
      context_package: context_package,
      context_entries: context_entries
    }
  end

  defp lock_invocation_identity!(binding_id, run_id, idempotency_key) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "agent-runtime:invoke:#{binding_id}:#{run_id}:#{idempotency_key}"
    ])
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}
end
