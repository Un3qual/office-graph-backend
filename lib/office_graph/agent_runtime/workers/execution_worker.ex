defmodule OfficeGraph.AgentRuntime.ExecutionWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{AgentRuntime, CommandSupport, DurableDelivery, Operations}
  alias OfficeGraph.Integrations.IntegrationCredential

  alias OfficeGraph.AgentRuntime.{
    ActionSupport,
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
    ExecutionWorkerActionResult,
    GateExpiryWorker,
    ModelInput,
    ModelRequest,
    OutputRouter,
    StorageResult
  }

  require Ash.Query

  @initial_step_key "model:review"
  @initial_fixture_id "proposal"
  @worker_timeout_ms :timer.minutes(3)
  @lease_seconds div(@worker_timeout_ms, 1_000) + 30
  @retry_delay_seconds 1
  @terminal_retry_delay_seconds 5

  @behaviour Ash.Resource.Actions.Implementation

  @impl Ash.Resource.Actions.Implementation
  def run(input, [mode: :claim], _context) do
    attrs = input.arguments

    worker_context = %{
      approval_request_id: attrs.approval_request_id,
      context_expansion_request_id: attrs.context_expansion_request_id,
      context_package: attrs.context_package,
      credential_kinds: attrs.credential_kinds,
      manifest: attrs.manifest,
      snapshot: attrs.snapshot
    }

    case claim_records(
           worker_context,
           attrs.operation_id,
           attrs.execution_id,
           attrs.step_key,
           attrs.fixture_id,
           attrs.lease_token
         ) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(AgentExecution, error)
    end
  end

  def run(input, [mode: :complete], _context) do
    attrs = input.arguments

    case complete_records(
           attrs.operation_id,
           attrs.execution_id,
           attrs.request_id,
           attrs.lease_token,
           attrs.context_package,
           attrs.output
         ) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(AgentExecution, error)
    end
  end

  def run(input, [mode: :fail_unclaimed], _context) do
    attrs = input.arguments

    case fail_unclaimed_records(attrs.operation_id, attrs.execution_id, attrs.failure_code) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(AgentExecution, error)
    end
  end

  def run(input, [mode: :finalize], _context) do
    attrs = input.arguments

    case finalize_records(
           attrs.operation_id,
           attrs.execution_id,
           attrs.request_id,
           attrs.lease_token,
           attrs.request_state,
           attrs.execution_state,
           attrs.failure_code
         ) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> ActionSupport.rollback(AgentExecution, error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

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
    args =
      execution
      |> initial_args(request.operation_id)
      |> Map.put(:approval_request_id, request.id)

    args =
      if is_binary(request.context_expansion_request_id),
        do: Map.put(args, :context_expansion_request_id, request.context_expansion_request_id),
        else: args

    args |> new() |> Oban.insert!()
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
  def timeout(_job), do: @worker_timeout_ms

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

      {:error, :integration_storage_unavailable} ->
        {:snooze, @retry_delay_seconds}

      {:error, {:terminal, failure_code}, execution, operation} ->
        fail_claim(execution.id, operation, job, failure_code)

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

    case revalidate_step(
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

          {:error, {:terminal, code}} ->
            failure_code = safe_code(code, "agent_adapter_authority_invalid")
            fail_claim(context.execution.id, operation, job, failure_code)

          {:error, _reason} ->
            fail_claim(context.execution.id, operation, job, "agent_step_claim_failed")
        end

      {:error, :integration_storage_unavailable} ->
        {:snooze, @retry_delay_seconds}

      {:error, _reason} ->
        with :ok <- fail_unclaimed_step(context.execution.id, operation) do
          finish_terminal_job(job, "agent_authority_revoked")
        end
    end
  end

  defp run_claim_result({:run, claim}, operation, job) do
    case claim_dispatch_posture(
           claim.execution.id,
           claim.request.id,
           claim.lease_token
         ) do
      :current ->
        claim.adapter
        |> invoke_safely(claim.input)
        |> persist_adapter_result(claim, operation, job)

      :completed ->
        :ok

      {:terminal, failure_code} ->
        finish_terminal_job(job, failure_code)

      :stale ->
        {:snooze, @retry_delay_seconds}

      {:error, :integration_storage_unavailable} ->
        {:snooze, @retry_delay_seconds}
    end
  end

  defp run_claim_result({:leased, delay}, _operation, _job), do: {:snooze, delay}
  defp run_claim_result({:waiting, _state, _execution, _request}, _operation, _job), do: :ok
  defp run_claim_result({:terminal, "completed", _execution}, _operation, _job), do: :ok

  defp run_claim_result({:terminal, state, execution}, _operation, job),
    do: finish_terminal_job(job, terminal_failure(execution, state))

  defp claim_dispatch_posture(execution_id, request_id, lease_token)
       when is_binary(execution_id) and is_binary(request_id) and is_binary(lease_token) do
    with {:ok, %ModelRequest{} = request} <-
           Ash.get(ModelRequest, request_id, authorize?: false, not_found_error?: false),
         true <- request.execution_id == execution_id,
         {:ok, %AgentExecution{} = execution} <-
           Ash.get(AgentExecution, execution_id,
             authorize?: false,
             not_found_error?: false
           ) do
      dispatch_posture(execution, request, lease_token)
    else
      {:ok, _missing_record} -> :stale
      false -> :stale
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp dispatch_posture(execution, request, lease_token) do
    cond do
      execution.state == "running" and execution.lease_token == lease_token and
        active_lease?(execution) and request.state == "running" ->
        :current

      execution.state == "completed" and request.state == "succeeded" ->
        :completed

      execution.state in ["failed", "cancelled"] ->
        {:terminal, safe_code(execution.failure_code, "agent_execution_#{execution.state}")}

      true ->
        :stale
    end
  end

  defp fail_claim(execution_id, operation, job, failure_code) do
    with :ok <- fail_unclaimed_step(execution_id, operation, failure_code) do
      finish_terminal_job(job, failure_code)
    end
  end

  defp load_context(execution_id, operation_id, organization_id, workspace_id, step_key) do
    with {:ok, %AgentExecution{} = execution} <- load_execution(execution_id),
         true <-
           execution.organization_id == organization_id and
             execution.workspace_id == workspace_id,
         {:ok, %AuthoritySnapshot{} = snapshot} <- authority_snapshot(execution.id),
         {:ok, operation} <- load_operation(operation_id),
         :ok <- validate_step_operation(operation, execution, snapshot, step_key) do
      load_runtime_context(execution, operation, snapshot)
    else
      false -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  defp load_runtime_context(execution, operation, snapshot) do
    with {:ok, %AgentDefinition{} = definition} <- load_definition(execution.definition_id),
         {:ok, %ContextPackage{} = context_package} <- context_package(execution.id),
         {:ok, adapter} <-
           AdapterRegistry.model(snapshot.model_adapter_key, snapshot.model_adapter_version),
         {:ok, credential_kinds} <- snapshot_credential_kinds(snapshot, execution) do
      {:ok,
       %{
         adapter: adapter,
         credential_kinds: credential_kinds,
         context_package: context_package,
         definition: definition,
         execution: execution,
         manifest: adapter.manifest(),
         operation: operation,
         snapshot: snapshot
       }}
    else
      {:error, :integration_storage_unavailable} = error ->
        error

      {:error, reason} when reason in [:adapter_not_found, :adapter_version_mismatch] ->
        {:error, {:terminal, "agent_adapter_unavailable"}, execution, operation}

      {:error, _invalid_runtime_context} ->
        {:error, {:terminal, "agent_context_unavailable"}, execution, operation}
    end
  end

  defp load_execution(execution_id) do
    case Ash.get(AgentExecution, execution_id, authorize?: false, not_found_error?: false) do
      {:ok, %AgentExecution{} = execution} -> {:ok, execution}
      {:ok, nil} -> {:error, :execution_not_found}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp load_definition(definition_id) do
    case Ash.get(AgentDefinition, definition_id, authorize?: false, not_found_error?: false) do
      {:ok, %AgentDefinition{} = definition} -> {:ok, definition}
      {:ok, nil} -> {:error, :definition_not_found}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp snapshot_credential_kinds(snapshot, execution) do
    Enum.reduce_while(snapshot.credential_ids, {:ok, []}, fn credential_id, {:ok, kinds} ->
      case Ash.get(IntegrationCredential, credential_id,
             authorize?: false,
             not_found_error?: false
           ) do
        {:ok, %IntegrationCredential{} = credential}
        when credential.organization_id == execution.organization_id and
               (is_nil(credential.workspace_id) or
                  credential.workspace_id == execution.workspace_id) ->
          case credential_kind(credential.kind) do
            {:ok, kind} -> {:cont, {:ok, [kind | kinds]}}
            {:error, _reason} = error -> {:halt, error}
          end

        {:ok, _missing_or_wrong_scope} ->
          {:halt, {:error, :credential_not_found}}

        {:error, _storage_error} ->
          {:halt, {:error, :integration_storage_unavailable}}
      end
    end)
    |> case do
      {:ok, kinds} -> {:ok, kinds |> Enum.uniq() |> Enum.sort()}
      {:error, _reason} = error -> error
    end
  end

  defp credential_kind("secret_reference"), do: {:ok, :secret_reference}
  defp credential_kind(_unsupported), do: {:error, :credential_kind_unsupported}

  defp load_operation(operation_id) do
    case Operations.read_operation(operation_id) do
      {:ok, operation} -> {:ok, operation}
      {:error, {:not_found, _resource, _id}} -> {:error, :operation_not_found}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp authority_snapshot(execution_id) do
    AuthoritySnapshot
    |> Ash.Query.filter(execution_id == ^execution_id and version == 1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %AuthoritySnapshot{} = snapshot} -> {:ok, snapshot}
      {:ok, nil} -> {:error, :authority_snapshot_missing}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp context_package(execution_id) do
    ContextPackage
    |> Ash.Query.filter(execution_id == ^execution_id)
    |> Ash.Query.sort(version: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %ContextPackage{} = context_package} -> {:ok, context_package}
      {:ok, nil} -> {:error, :context_package_missing}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp revalidate_step(execution_id, opts) do
    revalidator = Application.get_env(:office_graph, :agent_runtime_revalidator, AgentRuntime)
    revalidator.revalidate_step(execution_id, opts)
  end

  defp output_router do
    Application.get_env(:office_graph, :agent_runtime_output_router, OutputRouter)
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

    AgentExecution
    |> Ash.ActionInput.for_action(:claim_worker_step, %{
      operation_id: operation.id,
      execution_id: context.execution.id,
      step_key: step_key,
      fixture_id: fixture_id,
      lease_token: lease_token,
      snapshot: context.snapshot,
      context_package: context.context_package,
      manifest: context.manifest,
      credential_kinds: context.credential_kinds,
      approval_request_id: context.approval_request_id,
      context_expansion_request_id: context.context_expansion_request_id
    })
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
    |> case do
      {:ok, result} -> {:ok, claim_result(result, context)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp claim_records(
         context,
         operation_id,
         execution_id,
         step_key,
         fixture_id,
         lease_token
       ) do
    with {:ok, operation} <- Operations.lock_operation(operation_id),
         {:ok, %AgentExecution{} = execution} <- lock_execution(execution_id),
         :ok <- validate_claim_context(context, operation, execution, step_key) do
      case execution_posture(execution) do
        :available ->
          with {:ok, input} <-
                 model_input(context, operation, execution, step_key, fixture_id),
               :ok <- AdapterContract.validate_model_preflight(context.manifest, input) do
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
                  input,
                  lease_token
                )
            end
          end

        {:leased, delay} ->
          {:ok, ExecutionWorkerActionResult.build!(:leased, %{delay_seconds: delay})}

        {:waiting, state} ->
          {:ok,
           ExecutionWorkerActionResult.build!(:waiting, %{
             state: state,
             execution: execution
           })}

        {:terminal, state} ->
          {:ok,
           ExecutionWorkerActionResult.build!(:terminal, %{
             state: state,
             execution: execution
           })}
      end
    else
      {:ok, nil} -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_claim_context(context, operation, execution, step_key) do
    valid? =
      context.snapshot.execution_id == execution.id and
        context.context_package.execution_id == execution.id and
        context.context_package.authority_snapshot_id == context.snapshot.id

    if valid?,
      do: validate_step_operation(operation, execution, context.snapshot, step_key),
      else: {:error, :forbidden}
  end

  defp claim_result(%ExecutionWorkerActionResult{status: :run} = result, context) do
    {:run,
     %{
       adapter: context.adapter,
       context_package: context.context_package,
       execution: result.execution,
       input: result.input,
       lease_token: result.lease_token,
       manifest: context.manifest,
       request: result.model_request
     }}
  end

  defp claim_result(%ExecutionWorkerActionResult{status: :leased} = result, _context),
    do: {:leased, result.delay_seconds}

  defp claim_result(%ExecutionWorkerActionResult{status: :waiting} = result, _context) do
    request = result.approval_request || result.context_expansion_request
    {:waiting, result.state, result.execution, request}
  end

  defp claim_result(%ExecutionWorkerActionResult{status: :terminal} = result, _context),
    do: {:terminal, result.state, result.execution}

  defp wait_available_step(
         context,
         operation,
         execution,
         step_key,
         _fixture_id,
         waiting_state
       ) do
    with :ok <- ExecutionStateMachine.validate(execution.state, waiting_state),
         {:ok, waiting_request} <-
           prepare_waiting_request(waiting_state, context, operation, execution, step_key),
         {:ok, waiting} <-
           transition(execution, operation, waiting_state, %{
             current_step_key: step_key,
             failure_code: nil,
             lease_token: nil,
             lease_expires_at: nil
           }) do
      GateExpiryWorker.enqueue!(waiting_request)

      {:ok, waiting_result(waiting_state, waiting, waiting_request)}
    end
  end

  defp waiting_result("waiting_approval", execution, request) do
    ExecutionWorkerActionResult.build!(:waiting, %{
      state: "waiting_approval",
      execution: execution,
      approval_request: request
    })
  end

  defp waiting_result("waiting_context", execution, request) do
    ExecutionWorkerActionResult.build!(:waiting, %{
      state: "waiting_context",
      execution: execution,
      context_expansion_request: request
    })
  end

  defp claim_available_step(context, operation, execution, step_key, input, lease_token) do
    with :ok <- ExecutionStateMachine.validate(execution.state, "running"),
         :ok <- AdapterContract.validate_model_input(context.manifest, input),
         {:ok, credential_id} <- snapshotted_model_credential_id(context.snapshot),
         {:ok, request} <- create_or_load_request(context, operation, input, credential_id),
         :ok <- validate_request_replay(request, input, credential_id) do
      case request.state do
        "succeeded" ->
          with {:ok, completed} <-
                 transition(execution, operation, "completed", %{
                   completed_at: request.completed_at || DateTime.utc_now(),
                   failure_code: nil,
                   lease_token: nil,
                   lease_expires_at: nil
                 }) do
            {:ok,
             ExecutionWorkerActionResult.build!(:terminal, %{
               state: "completed",
               execution: completed
             })}
          end

        state when state in ["failed", "cancelled"] ->
          terminal_state = if state == "cancelled", do: "cancelled", else: "failed"

          with {:ok, terminal} <-
                 transition(execution, operation, terminal_state, %{
                   failure_code: request.failure_code,
                   lease_token: nil,
                   lease_expires_at: nil
                 }) do
            {:ok,
             ExecutionWorkerActionResult.build!(:terminal, %{
               state: terminal_state,
               execution: terminal
             })}
          end

        _active ->
          with {:ok, running_request} <-
                 request
                 |> Ash.Changeset.for_update(:record_result, %{state: "running"})
                 |> Ash.update(authorize?: false, return_notifications?: true)
                 |> CommandSupport.normalize_ash_write(),
               {:ok, running_execution} <-
                 transition(execution, operation, "running", %{
                   attempt_count: execution.attempt_count + 1,
                   current_step_key: step_key,
                   failure_code: nil,
                   lease_token: lease_token,
                   lease_expires_at: DateTime.add(DateTime.utc_now(), @lease_seconds, :second),
                   started_at: execution.started_at || DateTime.utc_now()
                 }) do
            {:ok,
             ExecutionWorkerActionResult.build!(:run, %{
               execution: running_execution,
               input: input,
               lease_token: lease_token,
               model_request: running_request
             })}
          end
      end
    end
  end

  defp complete(claim, operation, output) do
    StorageResult.run(fn ->
      AgentExecution
      |> Ash.ActionInput.for_action(:complete_worker_step, %{
        operation_id: operation.id,
        execution_id: claim.execution.id,
        request_id: claim.request.id,
        lease_token: claim.lease_token,
        context_package: claim.context_package,
        output: output
      })
      |> Ash.run_action(authorize?: false)
      |> ActionSupport.normalize_action_result()
      |> normalize_worker_action()
    end)
  end

  defp complete_records(
         operation_id,
         execution_id,
         request_id,
         lease_token,
         context_package,
         output
       ) do
    with {:ok, operation} <- Operations.lock_operation(operation_id),
         {:ok, %AgentExecution{} = execution} <- lock_execution(execution_id),
         {:ok, %ModelRequest{} = request} <- lock_model_request(request_id),
         true <- request.execution_id == execution.id do
      cond do
        execution.state == "cancelled" ->
          with :ok <- maybe_cancel_request(request, "cancelled") do
            ok_worker_result()
          end

        execution.lease_token == lease_token and execution.state == "running" ->
          complete_current_step(operation, execution, request, context_package, output)

        request.state == "succeeded" and execution.state == "completed" ->
          ok_worker_result()

        true ->
          {:error, :stale_agent_execution_lease}
      end
    else
      {:ok, nil} -> {:error, :stale_agent_execution_lease}
      false -> {:error, :stale_agent_execution_lease}
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_current_step(operation, execution, request, context_package, output) do
    now = DateTime.utc_now()

    output_router().route!(
      operation,
      execution,
      context_package,
      request.step_key,
      output
    )

    with {:ok, _request} <-
           request
           |> Ash.Changeset.for_update(:record_result, %{
             state: "succeeded",
             output_hash: hash(output),
             output_classification: Atom.to_string(output.classification),
             failure_code: nil,
             completed_at: now
           })
           |> Ash.update(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         {:ok, _execution} <-
           transition(execution, operation, "completed", %{
             completed_at: now,
             failure_code: nil,
             lease_token: nil,
             lease_expires_at: nil
           }) do
      ok_worker_result()
    end
  end

  defp fail_unclaimed_step(execution_id, operation, failure_code \\ "agent_authority_revoked") do
    AgentExecution
    |> Ash.ActionInput.for_action(:fail_unclaimed_worker_step, %{
      operation_id: operation.id,
      execution_id: execution_id,
      failure_code: failure_code
    })
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
    |> normalize_worker_action()
  end

  defp fail_unclaimed_records(operation_id, execution_id, failure_code) do
    with {:ok, operation} <- Operations.lock_operation(operation_id),
         {:ok, %AgentExecution{} = execution} <- lock_execution(execution_id) do
      if ExecutionStateMachine.terminal?(execution.state) do
        ok_worker_result()
      else
        with {:ok, _failed} <-
               transition(execution, operation, "failed", %{
                 completed_at: DateTime.utc_now(),
                 failure_code: failure_code,
                 lease_token: nil,
                 lease_expires_at: nil
               }) do
          ok_worker_result()
        end
      end
    else
      {:ok, nil} -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_adapter_result({:ok, output}, claim, operation, job) do
    case AdapterContract.validate_model_output(claim.manifest, output) do
      :ok ->
        case complete(claim, operation, output) do
          :ok ->
            :ok

          {:error, :integration_storage_unavailable} ->
            retry_or_exhaust(claim, operation, job, "integration_storage_unavailable")

          {:error, :stale_agent_execution_lease} ->
            {:snooze, @retry_delay_seconds}

          {:error, reason} ->
            failure_code = output_routing_failure_code(reason)

            with :ok <- fail_step(claim, operation, failure_code) do
              finish_terminal_job(job, failure_code)
            end
        end

      {:error, failure} ->
        persist_adapter_result({:error, failure}, claim, operation, job)
    end
  end

  defp persist_adapter_result({:error, {:retryable, code}}, claim, operation, job) do
    retry_or_exhaust(claim, operation, job, safe_code(code, "retryable_adapter_failure"))
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

  defp retry_or_exhaust(claim, operation, job, failure_code) do
    if claim.execution.attempt_count >= bounded_attempt_budget(job) do
      with :ok <- fail_step(claim, operation, "attempts_exhausted") do
        finish_terminal_job(job, "attempts_exhausted")
      end
    else
      with :ok <- retry_step(claim, operation, failure_code) do
        {:snooze, @retry_delay_seconds}
      end
    end
  end

  defp finalize_step(claim, operation, request_state, execution_state, failure_code) do
    AgentExecution
    |> Ash.ActionInput.for_action(:finalize_worker_step, %{
      operation_id: operation.id,
      execution_id: claim.execution.id,
      request_id: claim.request.id,
      lease_token: claim.lease_token,
      request_state: request_state,
      execution_state: execution_state,
      failure_code: failure_code
    })
    |> Ash.run_action(authorize?: false)
    |> ActionSupport.normalize_action_result()
    |> normalize_worker_action()
  end

  defp finalize_records(
         operation_id,
         execution_id,
         request_id,
         lease_token,
         request_state,
         execution_state,
         failure_code
       ) do
    with {:ok, operation} <- Operations.lock_operation(operation_id),
         {:ok, %AgentExecution{} = execution} <- lock_execution(execution_id),
         {:ok, %ModelRequest{} = request} <- lock_model_request(request_id),
         true <- request.execution_id == execution.id do
      cond do
        execution.state == "cancelled" ->
          with :ok <- maybe_cancel_request(request, failure_code) do
            ok_worker_result()
          end

        execution.lease_token == lease_token and execution.state == "running" ->
          finalize_current_step(
            operation,
            execution,
            request,
            request_state,
            execution_state,
            failure_code
          )

        true ->
          {:error, :stale_agent_execution_lease}
      end
    else
      {:ok, nil} -> {:error, :stale_agent_execution_lease}
      false -> {:error, :stale_agent_execution_lease}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalize_current_step(
         operation,
         execution,
         request,
         request_state,
         execution_state,
         failure_code
       ) do
    now = DateTime.utc_now()

    with {:ok, _request} <-
           request
           |> Ash.Changeset.for_update(:record_result, %{
             state: request_state,
             failure_code: failure_code,
             completed_at: if(request_state in ["failed", "cancelled"], do: now, else: nil)
           })
           |> Ash.update(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         {:ok, _execution} <-
           transition(
             execution,
             operation,
             execution_state,
             terminal_transition_attrs(execution_state, failure_code, now)
           ) do
      ok_worker_result()
    end
  end

  defp terminal_transition_attrs(execution_state, failure_code, now) do
    attrs = %{
      failure_code: failure_code,
      lease_token: nil,
      lease_expires_at: nil
    }

    case execution_state do
      "failed" -> Map.put(attrs, :completed_at, now)
      "cancelled" -> Map.put(attrs, :cancelled_at, now)
      _other -> attrs
    end
  end

  defp ok_worker_result,
    do: {:ok, ExecutionWorkerActionResult.build!(:ok)}

  defp normalize_worker_action({:ok, %ExecutionWorkerActionResult{status: :ok}}), do: :ok
  defp normalize_worker_action({:error, reason}), do: {:error, reason}

  defp create_or_load_request(_context, operation, input, credential_id) do
    case model_request(input.execution_id, input.step_key, input.idempotency_key) do
      {:ok, nil} ->
        ModelRequest
        |> Ash.Changeset.for_create(:create, %{
          id: input.request_id,
          execution_id: input.execution_id,
          context_package_id: input.context_package_id,
          authority_snapshot_id: input.authority_snapshot_id,
          credential_id: credential_id,
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
        |> Ash.create(authorize?: false, return_notifications?: true)
        |> CommandSupport.normalize_ash_write()

      {:ok, request} ->
        {:ok, request}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp model_request(execution_id, step_key, idempotency_key) do
    ModelRequest
    |> Ash.Query.filter(
      execution_id == ^execution_id and step_key == ^step_key and
        idempotency_key == ^idempotency_key
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp create_or_load_approval_request(context, operation, execution, step_key) do
    with {:ok, credential_id} <- snapshotted_model_credential_id(context.snapshot) do
      attrs = %{
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
        credential_id: credential_id,
        context_expansion_request_id: context.context_expansion_request_id,
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
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, nil} ->
          ApprovalRequest
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create(authorize?: false, return_notifications?: true)
          |> CommandSupport.normalize_ash_write()

        {:ok, request} ->
          validate_approval_request_replay(request, attrs)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp prepare_waiting_request("waiting_approval", context, operation, execution, step_key),
    do: create_or_load_approval_request(context, operation, execution, step_key)

  defp prepare_waiting_request("waiting_context", context, operation, execution, step_key),
    do: create_or_load_context_expansion_request(context, operation, execution, step_key)

  defp create_or_load_context_expansion_request(context, operation, execution, step_key) do
    target_result =
      ContextEntry
      |> Ash.Query.filter(
        context_package_id == ^context.context_package.id and posture == "expansion_required"
      )
      |> Ash.Query.sort(ordinal: :asc)
      |> Ash.Query.limit(1)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one(authorize?: false)

    capability_key = "agent.tool.read"

    with {:ok, %ContextEntry{} = target} <- target_result,
         true <- capability_key in context.snapshot.capability_keys do
      attrs = %{
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
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, nil} ->
          ContextExpansionRequest
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create(authorize?: false, return_notifications?: true)
          |> CommandSupport.normalize_ash_write()

        {:ok, request} ->
          validate_context_expansion_request_replay(request, attrs)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, nil} -> {:error, :context_expansion_target_missing}
      false -> {:error, :context_expansion_not_authorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_context_expansion_request_replay(request, attrs) do
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
      do: {:ok, request},
      else: {:error, :agent_context_expansion_request_conflict}
  end

  defp validate_approval_request_replay(request, attrs) do
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
          :credential_id,
          :context_expansion_request_id,
          :sensitivity,
          :external_write,
          :state,
          :version
        ],
        &(Map.get(request, &1) == Map.get(attrs, &1))
      )

    if valid?, do: {:ok, request}, else: {:error, :agent_approval_request_conflict}
  end

  defp validate_request_replay(request, input, credential_id) do
    valid? =
      request.execution_id == input.execution_id and
        request.context_package_id == input.context_package_id and
        request.authority_snapshot_id == input.authority_snapshot_id and
        request.credential_id == credential_id and
        request.step_key == input.step_key and request.adapter_key == input.adapter_key and
        request.adapter_version == input.adapter_version and
        request.idempotency_key == input.idempotency_key and
        request.timeout_ms == input.timeout_ms and request.token_budget == input.token_budget and
        request.input_hash == encoded_fingerprint(input)

    if valid?, do: :ok, else: {:error, :agent_step_idempotency_conflict}
  end

  defp snapshotted_model_credential_id(%AuthoritySnapshot{credential_ids: []}), do: {:ok, nil}

  defp snapshotted_model_credential_id(%AuthoritySnapshot{credential_ids: [credential_id]}),
    do: {:ok, credential_id}

  defp snapshotted_model_credential_id(_snapshot), do: {:error, :authority_snapshot_invalid}

  defp model_input(context, operation, execution, step_key, fixture_id) do
    manifest = context.manifest

    with {:ok, existing_request_id} <- existing_request_id(execution.id, step_key) do
      {:ok,
       %ModelInput{
         request_id: existing_request_id || Ecto.UUID.generate(),
         execution_id: execution.id,
         step_key: step_key,
         context_package_id: context.context_package.id,
         authority_snapshot_id: context.snapshot.id,
         operation_id: operation.id,
         adapter_key: manifest.key,
         adapter_version: manifest.version,
         idempotency_key: step_idempotency_key(execution.id, step_key),
         capability_keys: context.snapshot.capability_keys,
         credential_kinds: context.credential_kinds,
         sensitivity: manifest.sensitivity,
         approval_granted?: is_binary(context.approval_request_id),
         timeout_ms: manifest.timeout_ms,
         token_budget: manifest.token_budget,
         adapter_payload: %{fixture_id: fixture_id}
       }}
    end
  end

  defp existing_request_id(execution_id, step_key) do
    ModelRequest
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.select([:id])
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:ok, nil}
      {:ok, request} -> {:ok, request.id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_execution(execution_id) do
    AgentExecution
    |> Ash.Query.filter(id == ^execution_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp lock_model_request(request_id) do
    ModelRequest
    |> Ash.Query.filter(id == ^request_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp transition(execution, operation, state, attrs) do
    with :ok <- ExecutionStateMachine.validate(execution.state, state),
         {:ok, updated} <-
           execution
           |> Ash.Changeset.for_update(:transition, Map.put(attrs, :state, state))
           |> Ash.update(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         :ok <- record_transition_event(operation, updated) do
      {:ok, updated}
    end
  end

  defp record_transition_event(operation, execution) do
    case DurableDelivery.record_system_and_enqueue(operation, %{
           event_key: "agent-execution:#{execution.id}:v#{execution.state_version}",
           event_kind: "agent_execution.#{execution.state}",
           subject_kind: "agent_execution",
           subject_id: execution.id,
           subject_version: execution.state_version
         }) do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_cancel_request(%ModelRequest{state: state}, _failure_code)
       when state in ["succeeded", "failed", "cancelled"],
       do: :ok

  defp maybe_cancel_request(request, failure_code) do
    request
    |> Ash.Changeset.for_update(:record_result, %{
      state: "cancelled",
      failure_code: failure_code,
      completed_at: DateTime.utc_now()
    })
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
    |> case do
      {:ok, _request} -> :ok
      {:error, reason} -> {:error, reason}
    end
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

  defp output_routing_failure_code({:agent_output_kind_not_allowed, _output_kind}),
    do: "agent_output_kind_not_allowed"

  defp output_routing_failure_code(_reason), do: "agent_output_routing_failed"

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
