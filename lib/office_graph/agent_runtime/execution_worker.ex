defmodule OfficeGraph.AgentRuntime.ExecutionWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{AgentRuntime, DurableDelivery, Operations, Repo}

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterRegistry,
    AdapterResult,
    AgentDefinition,
    AgentExecution,
    ApprovalRequest,
    AuthoritySnapshot,
    ContextEntry,
    ContextExpansionRequest,
    ContextPackage,
    ExecutionStateMachine,
    GateExpiryWorker,
    ModelInput,
    ModelRequest,
    OutputRouter
  }

  require Ash.Query

  @initial_step_key "model:review"
  @initial_fixture_id "proposal"
  @lease_seconds 30
  @retry_delay_seconds 1
  @terminal_retry_delay_seconds 5

  def prepare_initial(%AgentExecution{} = execution, %AuthoritySnapshot{} = snapshot) do
    with {:ok, operation} <- create_step_operation(execution, snapshot, @initial_step_key),
         {:ok, job} <-
           execution
           |> initial_args(operation.id)
           |> new()
           |> Oban.insert() do
      {:ok, %{operation: operation, job: job}}
    end
  end

  @doc false
  def enqueue_approval_resume!(%AgentExecution{} = execution, %ApprovalRequest{} = request) do
    execution
    |> initial_args(request.operation_id)
    |> Map.put(:approval_request_id, request.id)
    |> new()
    |> Oban.insert!()
  end

  @doc false
  def enqueue_context_expansion_resume!(
        %AgentExecution{} = execution,
        %ContextExpansionRequest{} = request
      ) do
    execution
    |> initial_args(request.operation_id)
    |> Map.put(:context_expansion_request_id, request.id)
    |> new()
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args:
            %{
              "execution_id" => execution_id,
              "fixture_id" => fixture_id,
              "operation_id" => operation_id,
              "organization_id" => organization_id,
              "step_key" => step_key,
              "workspace_id" => workspace_id
            } = args
        } = job
      )
      when is_binary(execution_id) and is_binary(fixture_id) and
             is_binary(operation_id) and is_binary(organization_id) and is_binary(step_key) and
             is_binary(workspace_id) do
    case load_context(execution_id, operation_id, organization_id, workspace_id, step_key) do
      {:ok, context} ->
        context = Map.put(context, :approval_request_id, Map.get(args, "approval_request_id"))

        context =
          Map.put(
            context,
            :context_expansion_request_id,
            Map.get(args, "context_expansion_request_id")
          )

        perform_context(context, step_key, fixture_id, job)

      {:error, _reason} ->
        finish_terminal_job(job, "invalid_agent_job_scope")
    end
  end

  def perform(_job), do: {:cancel, "invalid_agent_job"}

  defp perform_context(context, step_key, fixture_id, job) do
    case execution_posture(context.execution) do
      :available -> run_available_step(context, step_key, fixture_id, job)
      {:leased, delay} -> {:snooze, delay}
      {:waiting, _state} -> :ok
      {:terminal, "completed"} -> :ok
      {:terminal, state} -> finish_terminal_job(job, terminal_failure(context.execution, state))
    end
  end

  defp run_available_step(context, step_key, fixture_id, job) do
    operation = context.operation

    case AgentRuntime.revalidate_step(
           context.execution.id,
           approval_request_id: context.approval_request_id,
           context_expansion_request_id: context.context_expansion_request_id
         ) do
      :ok ->
        with {:ok, claim_result} <- claim(context, operation, step_key, fixture_id) do
          run_claim_result(claim_result, operation, job)
        else
          {:error, :context_expansion_not_authorized} ->
            fail_claim(
              context.execution.id,
              operation,
              job,
              "agent_context_expansion_not_authorized"
            )

          {:error, _reason} ->
            fail_claim(context.execution.id, operation, job, "agent_step_claim_failed")
        end

      {:error, _reason} ->
        with :ok <- fail_unclaimed_step(context.execution.id, operation) do
          finish_terminal_job(job, "agent_authority_revoked")
        end
    end
  end

  defp run_claim_result({:run, claim}, operation, job) do
    claim.adapter
    |> invoke_safely(claim.input)
    |> persist_adapter_result(claim, operation, job)
  end

  defp run_claim_result({:leased, delay}, _operation, _job), do: {:snooze, delay}
  defp run_claim_result({:waiting, _state, _execution, _request}, _operation, _job), do: :ok
  defp run_claim_result({:terminal, "completed", _execution}, _operation, _job), do: :ok

  defp run_claim_result({:terminal, state, execution}, _operation, job),
    do: finish_terminal_job(job, terminal_failure(execution, state))

  defp fail_claim(execution_id, operation, job, failure_code) do
    with :ok <- fail_unclaimed_step(execution_id, operation, failure_code) do
      finish_terminal_job(job, failure_code)
    end
  end

  defp load_context(execution_id, operation_id, organization_id, workspace_id, step_key) do
    with {:ok, %AgentExecution{} = execution} <-
           Ash.get(AgentExecution, execution_id, authorize?: false, not_found_error?: false),
         true <-
           execution.organization_id == organization_id and
             execution.workspace_id == workspace_id,
         {:ok, %AgentDefinition{} = definition} <-
           Ash.get(AgentDefinition, execution.definition_id,
             authorize?: false,
             not_found_error?: false
           ),
         {:ok, %AuthoritySnapshot{} = snapshot} <- authority_snapshot(execution.id),
         {:ok, %ContextPackage{} = context_package} <- context_package(execution.id),
         {:ok, adapter} <- AdapterRegistry.model(definition.model_adapter_key),
         {:ok, operation} <- Operations.read_operation(operation_id),
         :ok <- validate_step_operation(operation, execution, snapshot, step_key) do
      {:ok,
       %{
         adapter: adapter,
         context_package: context_package,
         definition: definition,
         execution: execution,
         manifest: adapter.manifest(),
         operation: operation,
         snapshot: snapshot
       }}
    else
      false -> {:error, :forbidden}
      {:ok, nil} -> {:error, :execution_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp authority_snapshot(execution_id) do
    AuthoritySnapshot
    |> Ash.Query.filter(execution_id == ^execution_id and version == 1)
    |> Ash.read_one(authorize?: false)
  end

  defp context_package(execution_id) do
    ContextPackage
    |> Ash.Query.filter(execution_id == ^execution_id)
    |> Ash.Query.sort(version: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one(authorize?: false)
  end

  defp create_step_operation(execution, snapshot, step_key) do
    attrs = %{
      organization_id: execution.organization_id,
      workspace_id: execution.workspace_id,
      principal_id: execution.agent_principal_id,
      action: :agent_runtime_execute,
      authority_basis: "agent-authority-snapshot:#{snapshot.id}",
      causation_key: "agent-execution:#{execution.id}",
      idempotency_scope: "agent-runtime:#{execution.id}",
      idempotency_key: "step:#{step_key}",
      subject_kind: "agent_execution",
      subject_id: execution.id
    }

    with {:ok, request} <- Operations.new_system_operation_request(attrs) do
      Operations.start_system_operation(request)
    end
  end

  defp validate_step_operation(operation, execution, snapshot, step_key) do
    valid? =
      operation.operation_kind == "system" and
        operation.organization_id == execution.organization_id and
        operation.workspace_id == execution.workspace_id and
        operation.principal_id == execution.agent_principal_id and
        operation.action == "agent.runtime.execute" and
        operation.authority_basis == "agent-authority-snapshot:#{snapshot.id}" and
        operation.causation_key == "agent-execution:#{execution.id}" and
        operation.idempotency_scope == "agent-runtime:#{execution.id}" and
        operation.idempotency_key == "step:#{step_key}" and
        operation.subject_kind == "agent_execution" and operation.subject_id == execution.id

    if valid?, do: :ok, else: {:error, :forbidden}
  end

  defp claim(context, operation, step_key, fixture_id) do
    lease_token = Ecto.UUID.generate()

    Repo.transaction(fn ->
      execution = lock_execution!(context.execution.id)

      case execution_posture(execution) do
        :available ->
          cond do
            context_requires_expansion?(context.context_package.id) ->
              wait_available_step(
                context,
                operation,
                execution,
                step_key,
                fixture_id,
                "waiting_context"
              )

            context.manifest.approval_required and is_nil(context.approval_request_id) ->
              wait_available_step(
                context,
                operation,
                execution,
                step_key,
                fixture_id,
                "waiting_approval"
              )

            true ->
              claim_available_step(
                context,
                operation,
                execution,
                step_key,
                fixture_id,
                lease_token
              )
          end

        {:leased, delay} ->
          {:leased, delay}

        {:waiting, state} ->
          {:waiting, state, execution, nil}

        {:terminal, state} ->
          {:terminal, state, execution}
      end
    end)
  end

  defp wait_available_step(
         context,
         operation,
         execution,
         step_key,
         _fixture_id,
         waiting_state
       ) do
    with :ok <- ExecutionStateMachine.validate(execution.state, waiting_state) do
      waiting_request =
        prepare_waiting_request!(waiting_state, context, operation, execution, step_key)

      waiting =
        transition!(execution, operation, waiting_state, %{
          current_step_key: step_key,
          failure_code: nil,
          lease_token: nil,
          lease_expires_at: nil
        })

      GateExpiryWorker.enqueue!(waiting_request)

      {:waiting, waiting_state, waiting, waiting_request}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp claim_available_step(context, operation, execution, step_key, fixture_id, lease_token) do
    with :ok <- ExecutionStateMachine.validate(execution.state, "running") do
      input = model_input(context, operation, execution, step_key, fixture_id)
      request = create_or_load_request!(context, operation, input)
      validate_request_replay!(request, input)

      case request.state do
        "succeeded" ->
          completed =
            transition!(execution, operation, "completed", %{
              completed_at: request.completed_at || DateTime.utc_now(),
              failure_code: nil,
              lease_token: nil,
              lease_expires_at: nil
            })

          {:terminal, "completed", completed}

        state when state in ["failed", "cancelled"] ->
          terminal_state = if state == "cancelled", do: "cancelled", else: "failed"

          terminal =
            transition!(execution, operation, terminal_state, %{
              failure_code: request.failure_code,
              lease_token: nil,
              lease_expires_at: nil
            })

          {:terminal, terminal_state, terminal}

        _active ->
          running_request =
            request
            |> Ash.Changeset.for_update(:record_result, %{state: "running"})
            |> Repo.ash_update!()

          running_execution =
            transition!(execution, operation, "running", %{
              attempt_count: execution.attempt_count + 1,
              current_step_key: step_key,
              failure_code: nil,
              lease_token: lease_token,
              lease_expires_at: DateTime.add(DateTime.utc_now(), @lease_seconds, :second),
              started_at: execution.started_at || DateTime.utc_now()
            })

          {:run,
           %{
             adapter: context.adapter,
             context_package: context.context_package,
             execution: running_execution,
             input: input,
             lease_token: lease_token,
             request: running_request
           }}
      end
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp complete(claim, operation, output) do
    Repo.transaction(fn ->
      execution = lock_execution!(claim.execution.id)
      request = lock_model_request!(claim.request.id)

      cond do
        execution.state == "cancelled" ->
          maybe_cancel_request!(request, "cancelled")
          :ok

        execution.lease_token == claim.lease_token and execution.state == "running" ->
          now = DateTime.utc_now()

          OutputRouter.route!(
            operation,
            execution,
            claim.context_package,
            request.step_key,
            output
          )

          request
          |> Ash.Changeset.for_update(:record_result, %{
            state: "succeeded",
            output_hash: hash(output),
            output_classification: Atom.to_string(output.classification),
            failure_code: nil,
            completed_at: now
          })
          |> Repo.ash_update!()

          transition!(execution, operation, "completed", %{
            completed_at: now,
            failure_code: nil,
            lease_token: nil,
            lease_expires_at: nil
          })

          :ok

        request.state == "succeeded" and execution.state == "completed" ->
          :ok

        true ->
          Repo.rollback(:stale_agent_execution_lease)
      end
    end)
    |> normalize_step_transaction()
  end

  defp fail_unclaimed_step(execution_id, operation, failure_code \\ "agent_authority_revoked") do
    Repo.transaction(fn ->
      execution = lock_execution!(execution_id)

      if ExecutionStateMachine.terminal?(execution.state) do
        :ok
      else
        transition!(execution, operation, "failed", %{
          completed_at: DateTime.utc_now(),
          failure_code: failure_code,
          lease_token: nil,
          lease_expires_at: nil
        })

        :ok
      end
    end)
    |> normalize_step_transaction()
  end

  defp persist_adapter_result({:ok, output}, claim, operation, _job),
    do: complete(claim, operation, output)

  defp persist_adapter_result({:error, {:retryable, code}}, claim, operation, job) do
    if claim.execution.attempt_count >= bounded_attempt_budget(job) do
      with :ok <- fail_step(claim, operation, "attempts_exhausted") do
        finish_terminal_job(job, "attempts_exhausted")
      end
    else
      failure_code = safe_code(code, "retryable_adapter_failure")

      with :ok <- retry_step(claim, operation, failure_code) do
        {:snooze, @retry_delay_seconds}
      end
    end
  end

  defp persist_adapter_result({:error, {:terminal, code}}, claim, operation, job) do
    failure_code = safe_code(code, "terminal_adapter_failure")

    with :ok <- fail_step(claim, operation, failure_code) do
      finish_terminal_job(job, failure_code)
    end
  end

  defp persist_adapter_result({:error, {:cancelled, code}}, claim, operation, job) do
    failure_code = safe_code(code, "cancelled")

    with :ok <- cancel_step(claim, operation, failure_code) do
      finish_terminal_job(job, failure_code)
    end
  end

  defp retry_step(claim, operation, failure_code) do
    finalize_step(claim, operation, "retry_scheduled", "retry_scheduled", failure_code)
  end

  defp fail_step(claim, operation, failure_code) do
    finalize_step(claim, operation, "failed", "failed", failure_code)
  end

  defp cancel_step(claim, operation, failure_code) do
    finalize_step(claim, operation, "cancelled", "cancelled", failure_code)
  end

  defp finalize_step(claim, operation, request_state, execution_state, failure_code) do
    Repo.transaction(fn ->
      execution = lock_execution!(claim.execution.id)
      request = lock_model_request!(claim.request.id)

      cond do
        execution.state == "cancelled" ->
          maybe_cancel_request!(request, failure_code)
          :ok

        execution.lease_token == claim.lease_token and execution.state == "running" ->
          now = DateTime.utc_now()

          request
          |> Ash.Changeset.for_update(:record_result, %{
            state: request_state,
            failure_code: failure_code,
            completed_at: if(request_state in ["failed", "cancelled"], do: now, else: nil)
          })
          |> Repo.ash_update!()

          transition_attrs = %{
            failure_code: failure_code,
            lease_token: nil,
            lease_expires_at: nil
          }

          transition_attrs =
            case execution_state do
              "failed" -> Map.put(transition_attrs, :completed_at, now)
              "cancelled" -> Map.put(transition_attrs, :cancelled_at, now)
              _other -> transition_attrs
            end

          transition!(execution, operation, execution_state, transition_attrs)
          :ok

        true ->
          Repo.rollback(:stale_agent_execution_lease)
      end
    end)
    |> normalize_step_transaction()
  end

  defp normalize_step_transaction({:ok, :ok}), do: :ok
  defp normalize_step_transaction({:error, reason}), do: {:error, reason}

  defp create_or_load_request!(context, operation, input) do
    case model_request(context.execution.id, input.step_key, input.idempotency_key) do
      nil ->
        Repo.ash_create!(ModelRequest, %{
          id: input.request_id,
          execution_id: input.execution_id,
          context_package_id: input.context_package_id,
          authority_snapshot_id: input.authority_snapshot_id,
          credential_id: context.definition.model_credential_id,
          operation_id: operation.id,
          step_key: input.step_key,
          adapter_key: input.adapter_key,
          adapter_version: input.adapter_version,
          model_family: input.adapter_key,
          idempotency_key: input.idempotency_key,
          state: "pending",
          timeout_ms: input.timeout_ms,
          token_budget: input.token_budget,
          input_hash: encoded_fingerprint(input),
          requested_at: DateTime.utc_now()
        })

      request ->
        request
    end
  end

  defp model_request(execution_id, step_key, idempotency_key) do
    ModelRequest
    |> Ash.Query.filter(
      execution_id == ^execution_id and step_key == ^step_key and
        idempotency_key == ^idempotency_key
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp create_or_load_approval_request!(context, operation, execution, step_key) do
    attrs = %{
      id: Ecto.UUID.generate(),
      execution_id: execution.id,
      authority_snapshot_id: context.snapshot.id,
      organization_id: execution.organization_id,
      workspace_id: execution.workspace_id,
      operation_id: operation.id,
      step_key: step_key,
      execution_state_version: execution.state_version + 1,
      requested_action: "model.generate",
      reason: "adapter_requires_human_approval",
      scope_type: "workspace",
      scope_id: execution.workspace_id,
      capability_key: List.first(context.manifest.capability_keys),
      sensitivity: Atom.to_string(context.manifest.sensitivity),
      external_write: context.manifest.external_write,
      state: "pending",
      version: 1,
      expires_at: DateTime.add(DateTime.utc_now(), 900, :second)
    }

    ApprovalRequest
    |> Ash.Query.filter(
      execution_id == ^execution.id and step_key == ^step_key and state == "pending"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> Repo.ash_create!(ApprovalRequest, attrs)
      request -> validate_approval_request_replay!(request, attrs)
    end
  end

  defp prepare_waiting_request!("waiting_approval", context, operation, execution, step_key),
    do: create_or_load_approval_request!(context, operation, execution, step_key)

  defp prepare_waiting_request!("waiting_context", context, operation, execution, step_key),
    do: create_or_load_context_expansion_request!(context, operation, execution, step_key)

  defp create_or_load_context_expansion_request!(context, operation, execution, step_key) do
    target =
      ContextEntry
      |> Ash.Query.filter(
        context_package_id == ^context.context_package.id and posture == "expansion_required"
      )
      |> Ash.Query.sort(ordinal: :asc)
      |> Ash.Query.limit(1)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    if is_nil(target), do: Repo.rollback(:context_expansion_target_missing)

    capability_key = "agent.tool.read"

    unless capability_key in context.snapshot.capability_keys do
      Repo.rollback(:context_expansion_not_authorized)
    end

    attrs = %{
      id: Ecto.UUID.generate(),
      execution_id: execution.id,
      current_context_package_id: context.context_package.id,
      authority_snapshot_id: context.snapshot.id,
      organization_id: execution.organization_id,
      workspace_id: execution.workspace_id,
      operation_id: operation.id,
      step_key: step_key,
      execution_state_version: execution.state_version + 1,
      target_resource_type: target.resource_type,
      target_resource_id: target.resource_id,
      target_scope_type: "workspace",
      target_scope_id: target.workspace_id,
      access_mode: "read",
      capability_key: capability_key,
      reason: "context_entry_requires_expansion",
      sensitivity: "internal",
      expected_duration_seconds: 900,
      state: "pending",
      version: 1,
      expires_at: DateTime.add(DateTime.utc_now(), 900, :second)
    }

    ContextExpansionRequest
    |> Ash.Query.filter(
      execution_id == ^execution.id and step_key == ^step_key and state == "pending"
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> Repo.ash_create!(ContextExpansionRequest, attrs)
      request -> validate_context_expansion_request_replay!(request, attrs)
    end
  end

  defp validate_context_expansion_request_replay!(request, attrs) do
    fields = [
      :execution_id,
      :current_context_package_id,
      :authority_snapshot_id,
      :organization_id,
      :workspace_id,
      :operation_id,
      :step_key,
      :execution_state_version,
      :target_resource_type,
      :target_resource_id,
      :target_scope_type,
      :target_scope_id,
      :access_mode,
      :capability_key,
      :reason,
      :sensitivity,
      :expected_duration_seconds,
      :state,
      :version
    ]

    if Enum.all?(fields, &(Map.get(request, &1) == Map.get(attrs, &1))),
      do: request,
      else: Repo.rollback(:agent_context_expansion_request_conflict)
  end

  defp validate_approval_request_replay!(request, attrs) do
    valid? =
      Enum.all?(
        [
          :execution_id,
          :authority_snapshot_id,
          :organization_id,
          :workspace_id,
          :operation_id,
          :step_key,
          :execution_state_version,
          :requested_action,
          :reason,
          :scope_type,
          :scope_id,
          :capability_key,
          :sensitivity,
          :external_write,
          :state,
          :version
        ],
        &(Map.get(request, &1) == Map.get(attrs, &1))
      )

    if valid?, do: request, else: Repo.rollback(:agent_approval_request_conflict)
  end

  defp validate_request_replay!(request, input) do
    valid? =
      request.execution_id == input.execution_id and
        request.context_package_id == input.context_package_id and
        request.authority_snapshot_id == input.authority_snapshot_id and
        request.step_key == input.step_key and request.adapter_key == input.adapter_key and
        request.adapter_version == input.adapter_version and
        request.idempotency_key == input.idempotency_key and
        request.timeout_ms == input.timeout_ms and request.token_budget == input.token_budget and
        request.input_hash == encoded_fingerprint(input)

    unless valid?, do: Repo.rollback(:agent_step_idempotency_conflict)
  end

  defp model_input(context, operation, execution, step_key, fixture_id) do
    manifest = context.manifest

    %ModelInput{
      request_id: existing_request_id(execution.id, step_key) || Ecto.UUID.generate(),
      execution_id: execution.id,
      step_key: step_key,
      context_package_id: context.context_package.id,
      authority_snapshot_id: context.snapshot.id,
      operation_id: operation.id,
      adapter_key: manifest.key,
      adapter_version: manifest.version,
      idempotency_key: step_idempotency_key(execution.id, step_key),
      capability_keys: context.snapshot.capability_keys,
      credential_kinds: manifest.credential_kinds,
      sensitivity: manifest.sensitivity,
      approval_granted?: is_binary(context.approval_request_id),
      timeout_ms: manifest.timeout_ms,
      token_budget: manifest.token_budget,
      adapter_payload: %{fixture_id: fixture_id}
    }
  end

  defp existing_request_id(execution_id, step_key) do
    ModelRequest
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.select([:id])
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> nil
      request -> request.id
    end
  end

  defp lock_execution!(execution_id) do
    AgentExecution
    |> Ash.Query.filter(id == ^execution_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_model_request!(request_id) do
    ModelRequest
    |> Ash.Query.filter(id == ^request_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp transition!(execution, operation, state, attrs) do
    with :ok <- ExecutionStateMachine.validate(execution.state, state) do
      updated =
        execution
        |> Ash.Changeset.for_update(:transition, Map.put(attrs, :state, state))
        |> Repo.ash_update!()

      record_transition_event!(operation, updated)
      updated
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp record_transition_event!(operation, execution) do
    case DurableDelivery.record_system_and_enqueue(operation, %{
           event_key: "agent-execution:#{execution.id}:v#{execution.state_version}",
           event_kind: "agent_execution.#{execution.state}",
           subject_kind: "agent_execution",
           subject_id: execution.id,
           subject_version: execution.state_version
         }) do
      {:ok, _event} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp maybe_cancel_request!(%ModelRequest{state: state}, _failure_code)
       when state in ["succeeded", "failed", "cancelled"],
       do: :ok

  defp maybe_cancel_request!(request, failure_code) do
    request
    |> Ash.Changeset.for_update(:record_result, %{
      state: "cancelled",
      failure_code: failure_code,
      completed_at: DateTime.utc_now()
    })
    |> Repo.ash_update!()

    :ok
  end

  defp execution_posture(%AgentExecution{} = execution) do
    cond do
      ExecutionStateMachine.terminal?(execution.state) ->
        {:terminal, execution.state}

      execution.state == "running" and active_lease?(execution) ->
        {:leased, lease_delay(execution)}

      execution.state in ["waiting_approval", "waiting_context"] ->
        {:waiting, execution.state}

      true ->
        :available
    end
  end

  defp active_lease?(%{lease_token: token, lease_expires_at: %DateTime{} = expires_at})
       when is_binary(token) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  defp active_lease?(_execution), do: false

  defp context_requires_expansion?(context_package_id) do
    ContextEntry
    |> Ash.Query.filter(
      context_package_id == ^context_package_id and posture == "expansion_required"
    )
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
    |> is_struct(ContextEntry)
  end

  defp lease_delay(%{lease_expires_at: expires_at}) do
    max(DateTime.diff(expires_at, DateTime.utc_now(), :second), 1)
  end

  defp invoke_safely(adapter, input) do
    adapter.invoke(input)
    |> AdapterResult.normalize()
  catch
    _kind, _reason -> {:error, {:terminal, :adapter_crashed}}
  end

  defp bounded_attempt_budget(%Oban.Job{max_attempts: max_attempts})
       when is_integer(max_attempts) and max_attempts > 0,
       do: min(max_attempts, 3)

  defp bounded_attempt_budget(_job), do: 3

  defp finish_terminal_job(%Oban.Job{} = job, failure_code) do
    failure_code = safe_code(failure_code, "agent_step_failed")

    case DurableDelivery.stage_terminal_failure(job, failure_code) do
      :ok -> {:cancel, failure_code}
      {:error, _reason} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp terminal_failure(%AgentExecution{failure_code: failure_code}, state),
    do: safe_code(failure_code, "agent_execution_#{state}")

  defp encoded_fingerprint(input) do
    input |> AdapterContract.fingerprint() |> Base.encode16(case: :lower)
  end

  defp hash(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp safe_code(code, fallback) when is_atom(code), do: safe_code(Atom.to_string(code), fallback)

  defp safe_code(code, fallback) when is_binary(code) do
    if byte_size(code) in 1..128 and Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, code),
      do: code,
      else: fallback
  end

  defp safe_code(_code, fallback), do: fallback

  defp step_idempotency_key(execution_id, step_key),
    do: "agent-step:#{execution_id}:#{step_key}"

  defp initial_args(execution, operation_id) do
    %{
      execution_id: execution.id,
      fixture_id: @initial_fixture_id,
      operation_id: operation_id,
      organization_id: execution.organization_id,
      step_key: @initial_step_key,
      workspace_id: execution.workspace_id
    }
  end
end
