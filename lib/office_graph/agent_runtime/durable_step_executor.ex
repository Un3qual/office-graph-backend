defmodule OfficeGraph.AgentRuntime.DurableStepExecutor do
  @moduledoc false

  alias OfficeGraph.{DurableDelivery, Operations, Repo}

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterResult,
    AgentExecution,
    ExecutionLock,
    ExecutionStateMachine,
    ModelInput,
    ModelRequest,
    StorageResult,
    ToolInput,
    ToolRequest
  }

  require Ash.Query

  @lease_seconds 30
  @retry_delay_seconds 1
  @terminal_retry_delay_seconds 5

  @type context :: map()
  @type options :: [
          step: map(),
          build_input: (context(), AgentExecution.t() -> ModelInput.t() | ToolInput.t()),
          validate_input: (struct() -> :ok | {:error, term()}),
          preflight: (struct() -> :ok | {:error, term()}),
          before_claim: (context(), AgentExecution.t(), struct() -> :continue | {:return, term()}),
          validate_output: (struct() -> :ok | {:error, term()}),
          invoke: (struct() -> term()),
          revalidate: (context() -> :ok | {:error, term()}),
          prepare_context: (context() -> {:ok, context()} | {:error, term()}),
          advance: (AgentExecution.t(), struct(), struct(), DateTime.t() -> term()),
          completion_failure_code: (term() -> String.t())
        ]

  def perform(context, %Oban.Job{} = job, opts) when is_map(context) and is_list(opts) do
    step = Keyword.fetch!(opts, :step)

    case execution_posture(context.execution, step.key) do
      :available -> run_available_step(context, step, job, opts)
      :stale_step -> :ok
      {:leased, delay} -> {:snooze, delay}
      {:waiting, _state} -> :ok
      {:terminal, "completed"} -> :ok
      {:terminal, state} -> finish_terminal_job(job, terminal_failure(context.execution, state))
    end
  end

  def create_step_operation(%AgentExecution{} = execution, snapshot, step_key) do
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

  def validate_step_operation(operation, execution, snapshot, step_key) do
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

  def transition!(execution, operation, state, attrs) do
    with :ok <- ExecutionStateMachine.validate(execution.state, state) do
      updated =
        execution
        |> Ash.Changeset.for_update(:transition, Map.put(attrs, :state, state))
        |> Repo.ash_update!()

      case DurableDelivery.record_system_and_enqueue(operation, %{
             event_key: "agent-execution:#{updated.id}:v#{updated.state_version}",
             event_kind: "agent_execution.#{updated.state}",
             subject_kind: "agent_execution",
             subject_id: updated.id,
             subject_version: updated.state_version
           }) do
        {:ok, _event} -> updated
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def execution_posture(%AgentExecution{} = execution, step_key) do
    cond do
      ExecutionStateMachine.terminal?(execution.state) ->
        {:terminal, execution.state}

      is_binary(execution.current_step_key) and execution.current_step_key != step_key ->
        :stale_step

      execution.state == "running" and active_lease?(execution) ->
        {:leased, lease_delay(execution)}

      true ->
        if execution.state in ["waiting_approval", "waiting_context"],
          do: {:waiting, execution.state},
          else: :available
    end
  end

  def invoke_safely(adapter, input) when is_atom(adapter) do
    adapter.invoke(input)
    |> AdapterResult.normalize()
  catch
    _kind, _reason -> {:error, {:terminal, :adapter_crashed}}
  end

  def fingerprint(input) do
    input |> AdapterContract.fingerprint() |> Base.encode16(case: :lower)
  end

  def hash(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def step_idempotency_key(execution_id, step_key),
    do: "agent-step:#{execution_id}:#{step_key}"

  def safe_code(code, fallback) when is_atom(code), do: safe_code(Atom.to_string(code), fallback)

  def safe_code(code, fallback) when is_binary(code) do
    if byte_size(code) in 1..128 and Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, code),
      do: code,
      else: fallback
  end

  def safe_code(_code, fallback), do: fallback

  def finish_terminal_job(%Oban.Job{} = job, failure_code) do
    failure_code = safe_code(failure_code, "agent_step_failed")

    case DurableDelivery.stage_terminal_failure(job, failure_code) do
      :ok -> {:cancel, failure_code}
      {:error, _reason} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end

  def existing_request_id(resource, execution_id, step_key) do
    case request(resource, execution_id, step_key) do
      nil -> Ecto.UUID.generate()
      existing -> existing.id
    end
  end

  defp run_available_step(context, step, job, opts) do
    revalidate = Keyword.fetch!(opts, :revalidate)

    case revalidate.(context) do
      :ok ->
        prepare_context = Keyword.get(opts, :prepare_context, &{:ok, &1})

        case prepare_context.(context) do
          {:ok, prepared_context} ->
            claim_and_run(prepared_context, step, job, opts)

          {:error, :integration_storage_unavailable} ->
            {:snooze, @retry_delay_seconds}

          {:error, reason} ->
            failure = Keyword.get(opts, :claim_failure_code, &failure_code/1)
            fail_unclaimed(context, step, job, failure.(reason))
        end

      {:error, :integration_storage_unavailable} ->
        {:snooze, @retry_delay_seconds}

      {:error, reason} ->
        failure = Keyword.get(opts, :revalidation_failure_code, &failure_code/1)
        fail_unclaimed(context, step, job, failure.(reason))
    end
  end

  defp claim_and_run(context, step, job, opts) do
    case claim(context, step, opts) do
      {:ok, {:run, claim}} ->
        run_claim(claim, job, opts)

      {:ok, :already_succeeded} ->
        :ok

      {:ok, {:leased, delay}} ->
        {:snooze, delay}

      {:ok, {:waiting, _state, _execution, _request}} ->
        :ok

      {:ok, :stale_step} ->
        :ok

      {:ok, {:terminal, state, execution}} ->
        finish_terminal_job(job, terminal_failure(execution, state))

      {:error, reason} ->
        failure = Keyword.get(opts, :claim_failure_code, &failure_code/1)
        fail_unclaimed(context, step, job, failure.(reason))
    end
  end

  defp claim(context, step, opts) do
    lease_token = Ecto.UUID.generate()
    build_input = Keyword.fetch!(opts, :build_input)
    validate_input = Keyword.fetch!(opts, :validate_input)
    preflight = Keyword.get(opts, :preflight, validate_input)

    before_claim =
      Keyword.get(opts, :before_claim, fn _context, _execution, _input -> :continue end)

    Repo.transaction(fn ->
      execution = lock_execution!(context.execution.id)

      case execution_posture(execution, step.key) do
        :available ->
          input = build_input.(context, execution)

          with :ok <- preflight.(input) do
            case before_claim.(context, execution, input) do
              :continue ->
                with :ok <- validate_input.(input) do
                  claim_request(context, execution, input, step, lease_token)
                else
                  {:error, reason} -> Repo.rollback(reason)
                end

              {:return, result} ->
                result

              {:error, reason} ->
                Repo.rollback(reason)
            end
          else
            {:error, reason} -> Repo.rollback(reason)
          end

        :stale_step ->
          :stale_step

        {:leased, delay} ->
          {:leased, delay}

        {:waiting, state} ->
          {:waiting, state, execution, nil}

        {:terminal, state} ->
          {:terminal, state, execution}
      end
    end)
  end

  defp claim_request(context, execution, input, step, lease_token) do
    request = create_or_load_request!(context, input)
    validate_request_replay!(request, input, context)

    case request.state do
      "succeeded" ->
        :already_succeeded

      state when state in ["failed", "cancelled"] ->
        terminal_state = if state == "cancelled", do: "cancelled", else: "failed"
        {:terminal, terminal_state, execution}

      _active ->
        running_request = record_request_result!(request, %{state: "running"})

        running_execution =
          transition!(execution, context.operation, "running", %{
            attempt_count: execution.attempt_count + 1,
            current_step_key: step.key,
            failure_code: nil,
            lease_token: lease_token,
            lease_expires_at: DateTime.add(DateTime.utc_now(), @lease_seconds, :second),
            started_at: execution.started_at || DateTime.utc_now()
          })

        {:run,
         Map.merge(context, %{
           execution: running_execution,
           input: input,
           lease_token: lease_token,
           request: running_request,
           step: step
         })}
    end
  end

  defp run_claim(claim, job, opts) do
    invoke = Keyword.fetch!(opts, :invoke)

    claim.input
    |> invoke.()
    |> AdapterResult.normalize()
    |> persist_adapter_result(claim, job, opts)
  catch
    _kind, _reason ->
      persist_adapter_result({:error, {:terminal, :adapter_crashed}}, claim, job, opts)
  end

  defp persist_adapter_result({:ok, output}, claim, job, opts) do
    validate_output = Keyword.fetch!(opts, :validate_output)

    with :ok <- validate_output.(output) do
      case complete(claim, output, opts) do
        :ok ->
          :ok

        {:error, :integration_storage_unavailable} ->
          retry_or_exhaust(claim, job, "integration_storage_unavailable")

        {:error, :stale_agent_execution_lease} ->
          {:snooze, @retry_delay_seconds}

        {:error, reason} ->
          completion_failure_code = Keyword.fetch!(opts, :completion_failure_code)
          fail_claim(claim, job, completion_failure_code.(reason))
      end
    else
      {:error, {_classification, code}} ->
        fail_claim(claim, job, safe_code(code, "malformed_adapter_output"))
    end
  end

  defp persist_adapter_result({:error, {:retryable, code}}, claim, job, _opts),
    do: retry_or_exhaust(claim, job, safe_code(code, "retryable_adapter_failure"))

  defp persist_adapter_result({:error, {:terminal, code}}, claim, job, _opts),
    do: fail_claim(claim, job, safe_code(code, "terminal_adapter_failure"))

  defp persist_adapter_result({:error, {:cancelled, code}}, claim, job, _opts),
    do: fail_claim(claim, job, safe_code(code, "cancelled"), "cancelled", "cancelled")

  defp complete(claim, output, opts) do
    advance = Keyword.fetch!(opts, :advance)

    Repo.transaction(fn ->
      execution = lock_execution!(claim.execution.id)
      request = lock_request!(claim.request)

      cond do
        execution.state == "cancelled" ->
          record_request_result!(request, %{
            state: "cancelled",
            failure_code: execution.failure_code || "cancelled",
            completed_at: DateTime.utc_now()
          })

          :ok

        execution.lease_token == claim.lease_token and execution.state == "running" ->
          now = DateTime.utc_now()
          result_attrs = success_result_attrs(output, now)
          succeeded_request = record_request_result!(request, result_attrs)
          advance.(execution, succeeded_request, output, now)
          :ok

        request.state == "succeeded" ->
          :ok

        true ->
          Repo.rollback(:stale_agent_execution_lease)
      end
    end)
    |> normalize_transaction()
  rescue
    error in [Ash.Error.Forbidden, Ash.Error.Framework, Ash.Error.Invalid, Ash.Error.Unknown] ->
      {:error, error}
  end

  defp retry_or_exhaust(claim, job, failure_code) do
    if job.attempt >= bounded_attempt_budget(job) do
      fail_claim(claim, job, "attempts_exhausted")
    else
      case finalize_claim(claim, "retry_scheduled", "retry_scheduled", failure_code) do
        :ok -> {:snooze, @retry_delay_seconds}
        {:error, reason} -> finish_terminal_job(job, failure_code(reason))
      end
    end
  end

  defp fail_claim(
         claim,
         job,
         failure_code,
         request_state \\ "failed",
         execution_state \\ "failed"
       ) do
    case finalize_claim(claim, request_state, execution_state, failure_code) do
      :ok -> finish_terminal_job(job, failure_code)
      {:error, reason} -> finish_terminal_job(job, failure_code(reason))
    end
  end

  defp finalize_claim(claim, request_state, execution_state, failure_code) do
    Repo.transaction(fn ->
      execution = lock_execution!(claim.execution.id)
      request = lock_request!(claim.request)

      cond do
        execution.state == "cancelled" ->
          if request.state not in ["succeeded", "failed", "cancelled"] do
            record_request_result!(request, %{
              state: "cancelled",
              failure_code: execution.failure_code || failure_code,
              completed_at: DateTime.utc_now()
            })
          end

          :ok

        execution.lease_token == claim.lease_token and execution.state == "running" ->
          now = DateTime.utc_now()

          record_request_result!(request, %{
            state: request_state,
            failure_code: failure_code,
            completed_at: if(request_state in ["failed", "cancelled"], do: now, else: nil)
          })

          attrs = %{
            failure_code: failure_code,
            lease_token: nil,
            lease_expires_at: nil
          }

          attrs =
            case execution_state do
              "failed" -> Map.put(attrs, :completed_at, now)
              "cancelled" -> Map.put(attrs, :cancelled_at, now)
              _other -> attrs
            end

          transition!(execution, claim.operation, execution_state, attrs)
          :ok

        true ->
          Repo.rollback(:stale_agent_execution_lease)
      end
    end)
    |> normalize_transaction()
  end

  def fail_unclaimed(context, step, job, failure_code) do
    result =
      StorageResult.run(fn ->
        Repo.transaction(fn ->
          execution = lock_unclaimed_execution!(context.execution.id)

          case unclaimed_failure_posture(execution, step.key) do
            :available ->
              fail_execution!(execution, context.operation, step.key, failure_code)

              :failed

            {:reconcile, request} ->
              record_request_result!(request, %{
                state: "failed",
                failure_code: failure_code,
                completed_at: DateTime.utc_now()
              })

              fail_execution!(execution, context.operation, step.key, failure_code)

              :failed

            posture ->
              posture
          end
        end)
      end)

    case result do
      {:ok, :failed} ->
        finish_terminal_job(job, failure_code)

      {:ok, :stale_step} ->
        :ok

      {:ok, {:leased, delay}} ->
        {:snooze, delay}

      {:ok, {:claimed, delay}} ->
        {:snooze, delay}

      {:ok, {:waiting, _state}} ->
        :ok

      {:ok, {:terminal, "completed", _execution}} ->
        :ok

      {:ok, {:terminal, state, execution}} ->
        finish_terminal_job(job, terminal_failure(execution, state))

      {:error, :integration_storage_unavailable} ->
        {:snooze, @retry_delay_seconds}

      {:error, reason} ->
        finish_terminal_job(job, failure_code(reason))
    end
  end

  defp unclaimed_failure_posture(execution, step_key) do
    case execution_posture(execution, step_key) do
      :available ->
        request = step_request(execution.id, step_key)

        cond do
          execution.state == "queued" and is_nil(execution.lease_token) and
            is_nil(execution.lease_expires_at) and is_nil(request) ->
            :available

          matching_retry?(execution, request) ->
            {:reconcile, request}

          matching_expired_request?(execution, request) ->
            {:reconcile, request}

          true ->
            {:claimed, @retry_delay_seconds}
        end

      {:terminal, state} ->
        {:terminal, state, execution}

      posture ->
        posture
    end
  end

  defp step_request(execution_id, step_key) do
    request(ModelRequest, execution_id, step_key) ||
      request(ToolRequest, execution_id, step_key)
  end

  defp matching_retry?(%{state: "retry_scheduled"}, %{state: "retry_scheduled"}), do: true
  defp matching_retry?(_execution, _request), do: false

  defp matching_expired_request?(%{state: "running"} = execution, %{state: "running"}),
    do: not active_lease?(execution)

  defp matching_expired_request?(_execution, _request), do: false

  defp fail_execution!(execution, operation, step_key, failure_code) do
    transition!(execution, operation, "failed", %{
      current_step_key: step_key,
      completed_at: DateTime.utc_now(),
      failure_code: failure_code,
      lease_token: nil,
      lease_expires_at: nil
    })
  end

  defp lock_unclaimed_execution!(execution_id) do
    case unclaimed_execution_lock().lock_execution(execution_id) do
      {:ok, %AgentExecution{} = execution} -> execution
      {:ok, nil} -> Repo.rollback(:integration_storage_unavailable)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp unclaimed_execution_lock do
    Application.get_env(
      :office_graph,
      :agent_runtime_unclaimed_execution_lock,
      ExecutionLock
    )
  end

  defp create_or_load_request!(context, %ModelInput{} = input) do
    case request(ModelRequest, input.execution_id, input.step_key) do
      nil ->
        Repo.ash_create!(ModelRequest, %{
          id: input.request_id,
          execution_id: input.execution_id,
          context_package_id: input.context_package_id,
          authority_snapshot_id: input.authority_snapshot_id,
          credential_id: Map.get(context, :credential_id),
          operation_id: input.operation_id,
          step_key: input.step_key,
          adapter_key: input.adapter_key,
          adapter_version: input.adapter_version,
          model_family: input.adapter_key,
          idempotency_key: input.idempotency_key,
          state: "pending",
          timeout_ms: input.timeout_ms,
          token_budget: input.token_budget,
          input_hash: fingerprint(input),
          requested_at: DateTime.utc_now()
        })

      existing ->
        existing
    end
  end

  defp create_or_load_request!(_context, %ToolInput{} = input) do
    case request(ToolRequest, input.execution_id, input.step_key) do
      nil ->
        Repo.ash_create!(ToolRequest, %{
          id: input.request_id,
          execution_id: input.execution_id,
          context_package_id: input.context_package_id,
          authority_snapshot_id: input.authority_snapshot_id,
          credential_id: nil,
          operation_id: input.operation_id,
          step_key: input.step_key,
          tool_key: input.tool_key,
          adapter_version: input.adapter_version,
          idempotency_key: input.idempotency_key,
          state: "pending",
          sensitivity: Atom.to_string(input.sensitivity),
          external_write: false,
          timeout_ms: input.timeout_ms,
          budget_units: input.budget_units,
          input_hash: fingerprint(input),
          requested_at: DateTime.utc_now()
        })

      existing ->
        existing
    end
  end

  defp validate_request_replay!(%ModelRequest{} = request, %ModelInput{} = input, context) do
    valid? =
      request.execution_id == input.execution_id and
        request.context_package_id == input.context_package_id and
        request.authority_snapshot_id == input.authority_snapshot_id and
        request.credential_id == Map.get(context, :credential_id) and
        request.operation_id == input.operation_id and request.step_key == input.step_key and
        request.adapter_key == input.adapter_key and
        request.adapter_version == input.adapter_version and
        request.idempotency_key == input.idempotency_key and
        request.timeout_ms == input.timeout_ms and request.token_budget == input.token_budget and
        request.input_hash == fingerprint(input)

    unless valid?, do: Repo.rollback(:agent_step_idempotency_conflict)
  end

  defp validate_request_replay!(%ToolRequest{} = request, %ToolInput{} = input, _context) do
    valid? =
      request.execution_id == input.execution_id and
        request.context_package_id == input.context_package_id and
        request.authority_snapshot_id == input.authority_snapshot_id and
        request.operation_id == input.operation_id and request.step_key == input.step_key and
        request.tool_key == input.tool_key and request.adapter_version == input.adapter_version and
        request.idempotency_key == input.idempotency_key and
        request.timeout_ms == input.timeout_ms and request.budget_units == input.budget_units and
        request.external_write == false and request.input_hash == fingerprint(input)

    unless valid?, do: Repo.rollback(:agent_step_idempotency_conflict)
  end

  defp success_result_attrs(
         %{classification: classification, safe_summary: safe_summary} = output,
         now
       ) do
    %{
      state: "succeeded",
      output_hash: hash(output),
      output_classification: Atom.to_string(classification),
      failure_code: nil,
      completed_at: now
    }
    |> maybe_put_model_summary(output, safe_summary)
    |> maybe_put_tool_reference(output)
  end

  defp maybe_put_model_summary(attrs, %OfficeGraph.AgentRuntime.ModelOutput{}, safe_summary),
    do: Map.put(attrs, :output_safe_summary, safe_summary)

  defp maybe_put_model_summary(attrs, _output, _safe_summary), do: attrs

  defp maybe_put_tool_reference(attrs, %OfficeGraph.AgentRuntime.ToolOutput{} = output) do
    case get_in(output.structured_content, ["observation"]) do
      %{
        "reference" => reference,
        "content_hash" => content_hash,
        "byte_count" => byte_count
      }
      when is_binary(reference) and is_binary(content_hash) and is_integer(byte_count) and
             byte_count > 0 ->
        Map.merge(attrs, %{
          output_reference: reference,
          output_content_hash: content_hash,
          output_byte_count: byte_count
        })

      _non_reference_output ->
        attrs
    end
  end

  defp maybe_put_tool_reference(attrs, _output), do: attrs

  defp record_request_result!(request, attrs) do
    request
    |> Ash.Changeset.for_update(:record_result, attrs)
    |> Repo.ash_update!()
  end

  defp request(resource, execution_id, step_key) do
    resource
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_execution!(execution_id) do
    AgentExecution
    |> Ash.Query.filter(id == ^execution_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_request!(%ModelRequest{id: request_id}) do
    ModelRequest
    |> Ash.Query.filter(id == ^request_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_request!(%ToolRequest{id: request_id}) do
    ToolRequest
    |> Ash.Query.filter(id == ^request_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp active_lease?(%{lease_token: token, lease_expires_at: %DateTime{} = expires_at})
       when is_binary(token),
       do: DateTime.compare(expires_at, DateTime.utc_now()) == :gt

  defp active_lease?(_execution), do: false

  defp lease_delay(%{lease_expires_at: expires_at}),
    do: max(DateTime.diff(expires_at, DateTime.utc_now(), :second), 1)

  defp bounded_attempt_budget(%Oban.Job{max_attempts: max_attempts})
       when is_integer(max_attempts) and max_attempts > 0,
       do: min(max_attempts, 3)

  defp bounded_attempt_budget(_job), do: 3

  defp terminal_failure(%AgentExecution{failure_code: failure_code}, state),
    do: safe_code(failure_code, "agent_execution_#{state}")

  defp failure_code({:terminal, code}), do: failure_code(code)
  defp failure_code({:error, reason}), do: failure_code(reason)
  defp failure_code(code), do: safe_code(code, "agent_step_failed")

  defp normalize_transaction({:ok, :ok}), do: :ok
  defp normalize_transaction({:error, reason}), do: {:error, reason}
end
