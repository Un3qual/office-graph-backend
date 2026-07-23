defmodule OfficeGraph.AgentRuntime.Agents.OpenSpecReviewWorkflow do
  @moduledoc false

  alias OfficeGraph.{AgentRuntime, DurableDelivery, Operations, Repo}

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterRegistry,
    AdapterResult,
    AgentDefinition,
    AgentExecution,
    AuthoritySnapshot,
    ContextEntry,
    ContextPackage,
    ExecutionStateMachine,
    ExecutionWorker,
    ModelInput,
    ModelRequest,
    OutputRouter,
    ToolInput,
    ToolRequest
  }

  alias OfficeGraph.AgentRuntime.Tools.RepositoryRead

  require Ash.Query

  @workflow_key "openspec-review"
  @lease_seconds 30
  @retry_delay_seconds 1
  @terminal_retry_delay_seconds 5

  @step_templates [
    %{key: "context:repository", kind: :tool, adapter_key: "repository.read"},
    %{key: "context:openspec", kind: :tool, adapter_key: "openspec.read"},
    %{key: "review:message", kind: :model, fixture_id: "message"},
    %{key: "review:finding", kind: :model, fixture_id: "finding"},
    %{key: "review:proposal", kind: :model, fixture_id: "proposal"},
    %{key: "review:check", kind: :model, fixture_id: "observation"},
    %{key: "review:evidence", kind: :model, fixture_id: "evidence_candidate"}
  ]

  def steps, do: @step_templates

  def prepare_initial(%AgentExecution{} = execution, %AuthoritySnapshot{} = snapshot) do
    with {:ok, revision} <- RepositoryRead.pinned_revision(),
         first <- hd(@step_templates),
         {:ok, operation} <- create_step_operation(execution, snapshot, first.key),
         {:ok, job} <- enqueue_step(execution, snapshot, first, operation.id, revision) do
      {:ok, %{operation: operation, job: job}}
    end
  end

  def perform(
        %Oban.Job{
          args: %{
            "adapter_key" => adapter_key,
            "adapter_version" => adapter_version,
            "execution_id" => execution_id,
            "operation_id" => operation_id,
            "organization_id" => organization_id,
            "repository_revision" => repository_revision,
            "step_key" => step_key,
            "step_kind" => step_kind,
            "workflow_key" => @workflow_key,
            "workspace_id" => workspace_id
          }
        } = job
      ) do
    with {:ok, step} <- fetch_step(step_key),
         true <- Atom.to_string(step.kind) == step_kind,
         {:ok, context} <-
           load_context(
             execution_id,
             operation_id,
             organization_id,
             workspace_id,
             adapter_key,
             adapter_version,
             step,
             repository_revision
           ) do
      perform_context(context, job)
    else
      false -> finish_terminal_job(job, "invalid_openspec_review_step")
      {:error, :integration_storage_unavailable} -> {:snooze, @retry_delay_seconds}
      {:error, reason} -> finish_terminal_job(job, failure_code(reason))
    end
  end

  def perform(job), do: finish_terminal_job(job, "invalid_openspec_review_job")

  defp load_context(
         execution_id,
         operation_id,
         organization_id,
         workspace_id,
         adapter_key,
         adapter_version,
         step,
         repository_revision
       ) do
    with {:ok, %AgentExecution{} = execution} <- get(AgentExecution, execution_id),
         true <- execution.organization_id == organization_id,
         true <- execution.workspace_id == workspace_id,
         true <- execution.invocation_mode == "automatic",
         {:ok, %AgentDefinition{key: @workflow_key}} <-
           get(AgentDefinition, execution.definition_id),
         {:ok, %AuthoritySnapshot{} = snapshot} <- snapshot(execution.id),
         {:ok, %ContextPackage{} = context_package} <- context_package(execution.id),
         {:ok, operation} <- Operations.read_operation(operation_id),
         :ok <- validate_step_operation(operation, execution, snapshot, step.key),
         {:ok, adapter, manifest} <-
           resolve_adapter(step, snapshot, adapter_key, adapter_version) do
      {:ok,
       %{
         adapter: adapter,
         context_package: context_package,
         execution: execution,
         manifest: manifest,
         operation: operation,
         repository_revision: repository_revision,
         snapshot: snapshot,
         step: step
       }}
    else
      false -> {:error, :forbidden}
      {:ok, _wrong_definition} -> {:error, :forbidden}
      {:error, {:not_found, _resource, _id}} -> {:error, :forbidden}
      {:error, _reason} = error -> error
    end
  end

  defp perform_context(context, job) do
    execution = context.execution

    cond do
      execution.state == "completed" ->
        :ok

      ExecutionStateMachine.terminal?(execution.state) ->
        finish_terminal_job(job, execution.failure_code || "agent_execution_terminal")

      is_binary(execution.current_step_key) and execution.current_step_key != context.step.key ->
        :ok

      active_lease?(execution) ->
        {:snooze, lease_delay(execution)}

      true ->
        run_available_step(context, job)
    end
  end

  defp run_available_step(context, job) do
    opts = if context.step.kind == :tool, do: [tool_key: context.step.adapter_key], else: []

    case AgentRuntime.revalidate_step(context.execution.id, opts) do
      :ok ->
        case claim(context) do
          {:ok, {:run, claim}} -> run_claim(claim, job)
          {:ok, :already_succeeded} -> :ok
          {:ok, {:leased, delay}} -> {:snooze, delay}
          {:ok, :stale_step} -> :ok
          {:error, reason} -> fail_unclaimed(context, job, failure_code(reason))
        end

      {:error, :integration_storage_unavailable} ->
        {:snooze, @retry_delay_seconds}

      {:error, reason} ->
        fail_unclaimed(context, job, failure_code(reason))
    end
  end

  defp claim(context) do
    lease_token = Ecto.UUID.generate()

    Repo.transaction(fn ->
      execution = lock_execution!(context.execution.id)

      cond do
        ExecutionStateMachine.terminal?(execution.state) ->
          :stale_step

        is_binary(execution.current_step_key) and execution.current_step_key != context.step.key ->
          :stale_step

        active_lease?(execution) ->
          {:leased, lease_delay(execution)}

        execution.state not in ["queued", "retry_scheduled", "running"] ->
          Repo.rollback(:agent_step_not_available)

        true ->
          input = build_input(context)

          with :ok <- validate_input(context.step.kind, context.manifest, input) do
            request = create_or_load_request!(context, input)
            validate_request_replay!(request, input)

            if request.state == "succeeded" do
              :already_succeeded
            else
              running_request =
                request
                |> Ash.Changeset.for_update(:record_result, %{state: "running"})
                |> Repo.ash_update!()

              running_execution =
                transition!(execution, context.operation, "running", %{
                  attempt_count: execution.attempt_count + 1,
                  current_step_key: context.step.key,
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
                 request: running_request
               })}
            end
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  defp run_claim(claim, job) do
    claim.adapter
    |> invoke_safely(claim.input)
    |> persist_adapter_result(claim, job)
  end

  defp persist_adapter_result({:ok, output}, claim, job) do
    with :ok <- validate_output(claim.step.kind, claim.manifest, output) do
      case complete(claim, output) do
        :ok ->
          :ok

        {:error, :integration_storage_unavailable} ->
          retry_or_exhaust(claim, job, "integration_storage_unavailable")

        {:error, :stale_agent_execution_lease} ->
          {:snooze, @retry_delay_seconds}

        {:error, reason} ->
          fail_claim(claim, job, failure_code(reason))
      end
    else
      {:error, {_classification, code}} -> fail_claim(claim, job, Atom.to_string(code))
    end
  end

  defp persist_adapter_result({:error, {:retryable, code}}, claim, job),
    do: retry_or_exhaust(claim, job, failure_code(code))

  defp persist_adapter_result({:error, {:terminal, code}}, claim, job),
    do: fail_claim(claim, job, failure_code(code))

  defp persist_adapter_result({:error, {:cancelled, code}}, claim, job),
    do: fail_claim(claim, job, failure_code(code), "cancelled", "cancelled")

  defp complete(claim, output) do
    Repo.transaction(fn ->
      execution = lock_execution!(claim.execution.id)
      request = lock_request!(claim.step.kind, claim.request.id)

      cond do
        execution.state == "cancelled" ->
          record_request_result!(request, "cancelled", nil, nil, "cancelled", DateTime.utc_now())
          :ok

        execution.lease_token == claim.lease_token and execution.state == "running" ->
          now = DateTime.utc_now()

          if claim.step.kind == :model do
            OutputRouter.route!(
              claim.operation,
              execution,
              claim.context_package,
              claim.step.key,
              output
            )
          end

          record_request_result!(
            request,
            "succeeded",
            hash(output),
            Atom.to_string(output.classification),
            nil,
            now
          )

          case next_step(claim.step.key) do
            nil ->
              transition!(execution, claim.operation, "completed", %{
                current_step_key: claim.step.key,
                completed_at: now,
                failure_code: nil,
                lease_token: nil,
                lease_expires_at: nil
              })

            next ->
              queued =
                transition!(execution, claim.operation, "queued", %{
                  current_step_key: next.key,
                  failure_code: nil,
                  lease_token: nil,
                  lease_expires_at: nil
                })

              {:ok, operation} = create_step_operation(queued, claim.snapshot, next.key)

              case enqueue_step(
                     queued,
                     claim.snapshot,
                     next,
                     operation.id,
                     claim.repository_revision
                   ) do
                {:ok, _job} -> :ok
                {:error, reason} -> Repo.rollback(reason)
              end
          end

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
    if job.attempt >= min(job.max_attempts || 3, 3) do
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
      request = lock_request!(claim.step.kind, claim.request.id)

      if execution.lease_token == claim.lease_token and execution.state == "running" do
        now = DateTime.utc_now()

        record_request_result!(
          request,
          request_state,
          nil,
          nil,
          failure_code,
          if(request_state in ["failed", "cancelled"], do: now, else: nil)
        )

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
      else
        Repo.rollback(:stale_agent_execution_lease)
      end
    end)
    |> normalize_transaction()
  end

  defp fail_unclaimed(context, job, failure_code) do
    result =
      Repo.transaction(fn ->
        execution = lock_execution!(context.execution.id)

        if ExecutionStateMachine.terminal?(execution.state) do
          :ok
        else
          transition!(execution, context.operation, "failed", %{
            current_step_key: context.step.key,
            completed_at: DateTime.utc_now(),
            failure_code: failure_code,
            lease_token: nil,
            lease_expires_at: nil
          })

          :ok
        end
      end)
      |> normalize_transaction()

    case result do
      :ok -> finish_terminal_job(job, failure_code)
      {:error, reason} -> finish_terminal_job(job, failure_code(reason))
    end
  end

  defp build_input(%{step: %{kind: :tool}} = context) do
    manifest = context.manifest

    %ToolInput{
      request_id: existing_request_id(ToolRequest, context.execution.id, context.step.key),
      execution_id: context.execution.id,
      step_key: context.step.key,
      context_package_id: context.context_package.id,
      authority_snapshot_id: context.snapshot.id,
      operation_id: context.operation.id,
      tool_key: manifest.key,
      adapter_version: manifest.version,
      idempotency_key: step_idempotency_key(context.execution.id, context.step.key),
      capability_keys: context.snapshot.capability_keys,
      credential_kinds: [],
      timeout_ms: manifest.timeout_ms,
      budget_units: manifest.budget_units,
      sensitivity: manifest.sensitivity,
      external_write: false,
      approval_granted?: false,
      adapter_payload: tool_payload(context.step, context.repository_revision)
    }
  end

  defp build_input(%{step: %{kind: :model}} = context) do
    manifest = context.manifest
    {context_entry_ids, context_hashes} = context_references(context)

    %ModelInput{
      request_id: existing_request_id(ModelRequest, context.execution.id, context.step.key),
      execution_id: context.execution.id,
      step_key: context.step.key,
      context_package_id: context.context_package.id,
      authority_snapshot_id: context.snapshot.id,
      operation_id: context.operation.id,
      adapter_key: manifest.key,
      adapter_version: manifest.version,
      idempotency_key: step_idempotency_key(context.execution.id, context.step.key),
      capability_keys: context.snapshot.capability_keys,
      credential_kinds: [],
      sensitivity: manifest.sensitivity,
      approval_granted?: false,
      timeout_ms: manifest.timeout_ms,
      token_budget: manifest.token_budget,
      adapter_payload: %{
        fixture_id: context.step.fixture_id,
        context_entry_ids: context_entry_ids,
        context_hashes: context_hashes
      }
    }
  end

  defp context_references(context) do
    entries =
      ContextEntry
      |> Ash.Query.filter(context_package_id == ^context.context_package.id)
      |> Ash.Query.sort(ordinal: :asc)
      |> Ash.read!(authorize?: false)

    tool_hashes =
      ToolRequest
      |> Ash.Query.filter(execution_id == ^context.execution.id and state == "succeeded")
      |> Ash.Query.sort(step_key: :asc)
      |> Ash.Query.select([:output_hash])
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.output_hash)

    entry_hashes = Enum.map(entries, & &1.content_hash)

    hashes =
      [context.context_package.package_hash | entry_hashes ++ tool_hashes]
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.sort()

    {Enum.map(entries, & &1.id), hashes}
  end

  defp tool_payload(%{adapter_key: "repository.read"}, revision),
    do: %{path: "openspec/project.md", revision: revision}

  defp tool_payload(%{adapter_key: "openspec.read"}, _revision), do: %{action: "list"}

  defp create_or_load_request!(%{step: %{kind: :model}} = context, input) do
    case request(ModelRequest, context.execution.id, context.step.key) do
      nil ->
        Repo.ash_create!(ModelRequest, %{
          id: input.request_id,
          execution_id: input.execution_id,
          context_package_id: input.context_package_id,
          authority_snapshot_id: input.authority_snapshot_id,
          credential_id: nil,
          operation_id: input.operation_id,
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

      existing ->
        existing
    end
  end

  defp create_or_load_request!(%{step: %{kind: :tool}} = context, input) do
    case request(ToolRequest, context.execution.id, context.step.key) do
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
          input_hash: encoded_fingerprint(input),
          requested_at: DateTime.utc_now()
        })

      existing ->
        existing
    end
  end

  defp validate_request_replay!(%ModelRequest{} = request, %ModelInput{} = input) do
    valid? =
      request.execution_id == input.execution_id and
        request.context_package_id == input.context_package_id and
        request.authority_snapshot_id == input.authority_snapshot_id and
        request.operation_id == input.operation_id and request.step_key == input.step_key and
        request.adapter_key == input.adapter_key and
        request.adapter_version == input.adapter_version and
        request.idempotency_key == input.idempotency_key and
        request.timeout_ms == input.timeout_ms and request.token_budget == input.token_budget and
        request.input_hash == encoded_fingerprint(input)

    unless valid?, do: Repo.rollback(:agent_step_idempotency_conflict)
  end

  defp validate_request_replay!(%ToolRequest{} = request, %ToolInput{} = input) do
    valid? =
      request.execution_id == input.execution_id and
        request.context_package_id == input.context_package_id and
        request.authority_snapshot_id == input.authority_snapshot_id and
        request.operation_id == input.operation_id and request.step_key == input.step_key and
        request.tool_key == input.tool_key and request.adapter_version == input.adapter_version and
        request.idempotency_key == input.idempotency_key and
        request.timeout_ms == input.timeout_ms and request.budget_units == input.budget_units and
        request.external_write == false and request.input_hash == encoded_fingerprint(input)

    unless valid?, do: Repo.rollback(:agent_step_idempotency_conflict)
  end

  defp record_request_result!(
         request,
         state,
         output_hash,
         classification,
         failure_code,
         completed_at
       ) do
    request
    |> Ash.Changeset.for_update(:record_result, %{
      state: state,
      output_hash: output_hash,
      output_classification: classification,
      failure_code: failure_code,
      completed_at: completed_at
    })
    |> Repo.ash_update!()
  end

  defp resolve_adapter(%{kind: :tool, adapter_key: expected}, _snapshot, expected, version) do
    with {:ok, adapter} <- AdapterRegistry.tool(expected, version) do
      {:ok, adapter, adapter.manifest()}
    end
  end

  defp resolve_adapter(%{kind: :model}, snapshot, key, version)
       when key == snapshot.model_adapter_key and version == snapshot.model_adapter_version do
    with {:ok, adapter} <- AdapterRegistry.model(key, version) do
      {:ok, adapter, adapter.manifest()}
    end
  end

  defp resolve_adapter(_step, _snapshot, _key, _version), do: {:error, :adapter_not_found}

  defp enqueue_step(execution, snapshot, step, operation_id, revision) do
    with {:ok, adapter_key, adapter_version} <- adapter_identity(step, snapshot) do
      execution
      |> step_args(step, operation_id, revision, adapter_key, adapter_version)
      |> ExecutionWorker.new()
      |> Oban.insert()
    end
  end

  defp adapter_identity(%{kind: :tool, adapter_key: key}, _snapshot) do
    with {:ok, manifest} <- AdapterRegistry.tool_manifest(key) do
      {:ok, manifest.key, manifest.version}
    end
  end

  defp adapter_identity(%{kind: :model}, snapshot),
    do: {:ok, snapshot.model_adapter_key, snapshot.model_adapter_version}

  defp step_args(execution, step, operation_id, revision, adapter_key, adapter_version) do
    %{
      adapter_key: adapter_key,
      adapter_version: adapter_version,
      execution_id: execution.id,
      operation_id: operation_id,
      organization_id: execution.organization_id,
      repository_revision: revision,
      step_key: step.key,
      step_kind: Atom.to_string(step.kind),
      workflow_key: @workflow_key,
      workspace_id: execution.workspace_id
    }
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

  defp transition!(execution, operation, state, attrs) do
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

  defp get(resource, id) do
    case Ash.get(resource, id, authorize?: false, not_found_error?: false) do
      {:ok, nil} -> {:error, :forbidden}
      {:ok, record} -> {:ok, record}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp snapshot(execution_id) do
    AuthoritySnapshot
    |> Ash.Query.filter(execution_id == ^execution_id and version == 1)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %AuthoritySnapshot{} = snapshot} -> {:ok, snapshot}
      {:ok, nil} -> {:error, :forbidden}
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
      {:ok, %ContextPackage{} = package} -> {:ok, package}
      {:ok, nil} -> {:error, :forbidden}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp request(resource, execution_id, step_key) do
    resource
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp existing_request_id(resource, execution_id, step_key) do
    case request(resource, execution_id, step_key) do
      nil -> Ecto.UUID.generate()
      existing -> existing.id
    end
  end

  defp lock_execution!(execution_id) do
    AgentExecution
    |> Ash.Query.filter(id == ^execution_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp lock_request!(resource_kind, request_id) do
    resource = if resource_kind == :model, do: ModelRequest, else: ToolRequest

    resource
    |> Ash.Query.filter(id == ^request_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp fetch_step(step_key) do
    case Enum.find(@step_templates, &(&1.key == step_key)) do
      nil -> {:error, :invalid_openspec_review_step}
      step -> {:ok, step}
    end
  end

  defp next_step(step_key) do
    @step_templates
    |> Enum.drop_while(&(&1.key != step_key))
    |> Enum.at(1)
  end

  defp validate_input(:model, manifest, input),
    do: AdapterContract.validate_model_input(manifest, input)

  defp validate_input(:tool, manifest, input),
    do: AdapterContract.validate_tool_input(manifest, input)

  defp validate_output(:model, manifest, output),
    do: AdapterContract.validate_model_output(manifest, output)

  defp validate_output(:tool, manifest, output),
    do: AdapterContract.validate_tool_output(manifest, output)

  defp invoke_safely(adapter, input) do
    adapter.invoke(input)
    |> AdapterResult.normalize()
  catch
    _kind, _reason -> {:error, {:terminal, :adapter_crashed}}
  end

  defp active_lease?(%{lease_token: token, lease_expires_at: %DateTime{} = expires_at})
       when is_binary(token),
       do: DateTime.compare(expires_at, DateTime.utc_now()) == :gt

  defp active_lease?(_execution), do: false

  defp lease_delay(execution),
    do: max(DateTime.diff(execution.lease_expires_at, DateTime.utc_now(), :second), 1)

  defp finish_terminal_job(%Oban.Job{} = job, failure_code) do
    failure_code = failure_code(failure_code)

    case DurableDelivery.stage_terminal_failure(job, failure_code) do
      :ok -> {:cancel, failure_code}
      {:error, _reason} -> {:snooze, @terminal_retry_delay_seconds}
    end
  end

  defp finish_terminal_job(_job, failure_code), do: {:cancel, failure_code(failure_code)}

  defp failure_code({:terminal, code}), do: failure_code(code)
  defp failure_code({:error, reason}), do: failure_code(reason)
  defp failure_code(code) when is_atom(code), do: failure_code(Atom.to_string(code))

  defp failure_code(code) when is_binary(code) do
    if byte_size(code) in 1..128 and Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, code),
      do: code,
      else: "openspec_review_step_failed"
  end

  defp failure_code(_code), do: "openspec_review_step_failed"

  defp normalize_transaction({:ok, :ok}), do: :ok
  defp normalize_transaction({:error, reason}), do: {:error, reason}

  defp encoded_fingerprint(input) do
    input |> AdapterContract.fingerprint() |> Base.encode16(case: :lower)
  end

  defp hash(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp step_idempotency_key(execution_id, step_key),
    do: "agent-step:#{execution_id}:#{step_key}"
end
