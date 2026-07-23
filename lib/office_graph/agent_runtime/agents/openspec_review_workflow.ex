defmodule OfficeGraph.AgentRuntime.Agents.OpenSpecReviewWorkflow do
  @moduledoc false

  alias OfficeGraph.{AgentRuntime, Operations, Repo}

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterRegistry,
    AgentDefinition,
    AgentExecution,
    AuthoritySnapshot,
    ContextEntry,
    ContextPackage,
    DurableStepExecutor,
    ExecutionWorker,
    ModelInput,
    ModelRequest,
    OutputRouter,
    RoutedOutputBatch,
    ToolInput,
    ToolReferenceResolver,
    ToolRequest
  }

  alias OfficeGraph.AgentRuntime.Tools.RepositoryRead

  require Ash.Query

  @workflow_key "openspec-review"
  @retry_delay_seconds 1

  @steps [
    %{key: "context:repository", kind: :tool, adapter_key: "repository.read"},
    %{key: "context:openspec", kind: :tool, adapter_key: "openspec.read"},
    %{key: "model:review", kind: :model, fixture_id: "openspec_review"},
    %{key: "output:route", kind: :route, adapter_key: "internal.output.route"}
  ]

  def steps, do: @steps

  def prepare_initial(%AgentExecution{} = execution, %AuthoritySnapshot{} = snapshot) do
    with {:ok, revision} <- RepositoryRead.pinned_revision(),
         first <- hd(@steps),
         {:ok, operation} <-
           DurableStepExecutor.create_step_operation(execution, snapshot, first.key),
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
      false -> DurableStepExecutor.finish_terminal_job(job, "invalid_openspec_review_step")
      {:error, :integration_storage_unavailable} -> {:snooze, @retry_delay_seconds}
      {:error, reason} -> DurableStepExecutor.finish_terminal_job(job, failure_code(reason))
    end
  end

  def perform(job),
    do: DurableStepExecutor.finish_terminal_job(job, "invalid_openspec_review_job")

  defp perform_context(context, job) do
    step = context.step

    DurableStepExecutor.perform(context, job,
      step: step,
      build_input: &build_input/2,
      validate_input: &validate_input(step.kind, context.manifest, &1),
      validate_output: &validate_output(step.kind, context.manifest, &1),
      invoke: &DurableStepExecutor.invoke_safely(context.adapter, &1),
      revalidate: &revalidate_step(&1, step),
      prepare_context: &prepare_step_context/1,
      advance: &advance(context, &1, &2, &3, &4),
      completion_failure_code: &completion_failure_code/1
    )
  end

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
         :ok <-
           DurableStepExecutor.validate_step_operation(operation, execution, snapshot, step.key),
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

  defp prepare_step_context(%{step: %{kind: :model}} = context) do
    with {:ok, adapter_payload} <- review_payload(context) do
      {:ok, Map.put(context, :adapter_payload, adapter_payload)}
    end
  end

  defp prepare_step_context(%{step: %{kind: :route}} = context) do
    case model_review_request(context.execution.id) do
      %ModelRequest{
        state: "succeeded",
        context_package_id: context_package_id,
        authority_snapshot_id: authority_snapshot_id,
        output_hash: output_hash,
        output_safe_summary: output_safe_summary
      } = request
      when context_package_id == context.context_package.id and
             authority_snapshot_id == context.snapshot.id and is_binary(output_hash) and
             is_binary(output_safe_summary) ->
        {:ok, Map.put(context, :model_review_request, request)}

      _missing_or_invalid ->
        {:error, {:terminal, :model_review_result_unavailable}}
    end
  end

  defp prepare_step_context(context), do: {:ok, context}

  defp review_payload(context) do
    entries = context_entries(context.context_package.id)
    read_requests = read_requests(context.execution.id)

    with true <-
           Enum.map(read_requests, & &1.step_key) == ["context:repository", "context:openspec"],
         {:ok, references} <- dereference_all(context, read_requests) do
      context_hashes =
        [context.context_package.package_hash | Enum.map(entries, & &1.content_hash)] ++
          Enum.map(references, & &1.content_hash)

      review_digest =
        references
        |> Enum.map(&{&1.reference_id, &1.reference, &1.content_hash, &1.content})
        |> DurableStepExecutor.hash()

      {:ok,
       %{
         fixture_id: context.step.fixture_id,
         context_entry_ids: Enum.map(entries, & &1.id),
         context_hashes:
           context_hashes |> Enum.filter(&is_binary/1) |> Enum.uniq() |> Enum.sort(),
         tool_reference_ids: Enum.map(references, & &1.reference_id),
         tool_reference_hashes: Enum.map(references, & &1.content_hash),
         review_digest: review_digest
       }}
    else
      false -> {:error, {:terminal, :tool_reference_set_invalid}}
      {:error, _reason} = error -> error
    end
  end

  defp dereference_all(context, requests) do
    Enum.reduce_while(requests, {:ok, []}, fn request, {:ok, references} ->
      case ToolReferenceResolver.dereference(
             context.execution,
             context.snapshot,
             context.context_package,
             request
           ) do
        {:ok, reference} -> {:cont, {:ok, [reference | references]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, references} -> {:ok, Enum.reverse(references)}
      {:error, _reason} = error -> error
    end
  end

  defp build_input(%{step: %{kind: :model}} = context, execution) do
    manifest = context.manifest

    %ModelInput{
      request_id:
        DurableStepExecutor.existing_request_id(ModelRequest, execution.id, context.step.key),
      execution_id: execution.id,
      step_key: context.step.key,
      context_package_id: context.context_package.id,
      authority_snapshot_id: context.snapshot.id,
      operation_id: context.operation.id,
      adapter_key: manifest.key,
      adapter_version: manifest.version,
      idempotency_key: DurableStepExecutor.step_idempotency_key(execution.id, context.step.key),
      capability_keys: context.snapshot.capability_keys,
      credential_kinds: [],
      sensitivity: manifest.sensitivity,
      approval_granted?: false,
      timeout_ms: manifest.timeout_ms,
      token_budget: manifest.token_budget,
      adapter_payload: context.adapter_payload
    }
  end

  defp build_input(context, execution) do
    manifest = context.manifest

    %ToolInput{
      request_id:
        DurableStepExecutor.existing_request_id(ToolRequest, execution.id, context.step.key),
      execution_id: execution.id,
      step_key: context.step.key,
      context_package_id: context.context_package.id,
      authority_snapshot_id: context.snapshot.id,
      operation_id: context.operation.id,
      tool_key: manifest.key,
      adapter_version: manifest.version,
      idempotency_key: DurableStepExecutor.step_idempotency_key(execution.id, context.step.key),
      capability_keys: context.snapshot.capability_keys,
      credential_kinds: [],
      timeout_ms: manifest.timeout_ms,
      budget_units: manifest.budget_units,
      sensitivity: manifest.sensitivity,
      external_write: false,
      approval_granted?: false,
      adapter_payload: tool_payload(context)
    }
  end

  defp tool_payload(%{step: %{adapter_key: "repository.read"}, repository_revision: revision}),
    do: %{path: "openspec/project.md", revision: revision}

  defp tool_payload(%{step: %{adapter_key: "openspec.read"}}), do: %{action: "list"}

  defp tool_payload(%{step: %{kind: :route}, model_review_request: request}) do
    %{
      model_request_id: request.id,
      model_output_hash: request.output_hash,
      review_summary: request.output_safe_summary
    }
  end

  defp advance(context, execution, _request, output, now) do
    if context.step.kind == :route do
      route_outputs!(context, execution, output)
    end

    case next_step(context.step.key) do
      nil ->
        DurableStepExecutor.transition!(execution, context.operation, "completed", %{
          current_step_key: context.step.key,
          completed_at: now,
          failure_code: nil,
          lease_token: nil,
          lease_expires_at: nil
        })

      next ->
        queued =
          DurableStepExecutor.transition!(execution, context.operation, "queued", %{
            current_step_key: next.key,
            failure_code: nil,
            lease_token: nil,
            lease_expires_at: nil
          })

        {:ok, operation} =
          DurableStepExecutor.create_step_operation(queued, context.snapshot, next.key)

        case enqueue_step(
               queued,
               context.snapshot,
               next,
               operation.id,
               context.repository_revision
             ) do
          {:ok, _job} -> queued
          {:error, _reason} -> Repo.rollback(:agent_step_continuation_failed)
        end
    end
  end

  defp route_outputs!(context, execution, output) do
    with {:ok, %RoutedOutputBatch{outputs: outputs}} <-
           RoutedOutputBatch.from_tool_output(output) do
      Enum.each(outputs, fn routed_output ->
        OutputRouter.route!(
          context.operation,
          execution,
          context.context_package,
          context.step.key,
          routed_output
        )
      end)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp resolve_adapter(%{kind: :model}, snapshot, key, version)
       when key == snapshot.model_adapter_key and version == snapshot.model_adapter_version do
    with {:ok, adapter} <- AdapterRegistry.model(key, version) do
      {:ok, adapter, adapter.manifest()}
    end
  end

  defp resolve_adapter(%{adapter_key: expected}, _snapshot, expected, version) do
    with {:ok, adapter} <- AdapterRegistry.tool(expected, version) do
      {:ok, adapter, adapter.manifest()}
    end
  end

  defp resolve_adapter(_step, _snapshot, _key, _version), do: {:error, :adapter_not_found}

  defp enqueue_step(execution, snapshot, step, operation_id, revision) do
    with {:ok, adapter_key, adapter_version} <- adapter_identity(step, snapshot) do
      changeset =
        execution
        |> step_args(step, operation_id, revision, adapter_key, adapter_version)
        |> ExecutionWorker.new()

      step_enqueuer().insert(changeset)
    end
  end

  defp adapter_identity(%{kind: :model}, snapshot),
    do: {:ok, snapshot.model_adapter_key, snapshot.model_adapter_version}

  defp adapter_identity(%{adapter_key: key}, _snapshot) do
    with {:ok, manifest} <- AdapterRegistry.tool_manifest(key) do
      {:ok, manifest.key, manifest.version}
    end
  end

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

  defp revalidate_step(context, %{kind: :tool, adapter_key: adapter_key}),
    do: revalidator().revalidate_step(context.execution.id, tool_key: adapter_key)

  defp revalidate_step(context, _step),
    do: revalidator().revalidate_step(context.execution.id, [])

  defp revalidator do
    Application.get_env(:office_graph, :agent_runtime_revalidator, AgentRuntime)
  end

  defp validate_input(:model, manifest, input),
    do: AdapterContract.validate_model_input(manifest, input)

  defp validate_input(kind, manifest, input) when kind in [:tool, :route],
    do: AdapterContract.validate_tool_input(manifest, input)

  defp validate_output(:model, manifest, output),
    do: AdapterContract.validate_model_output(manifest, output)

  defp validate_output(kind, manifest, output) when kind in [:tool, :route],
    do: AdapterContract.validate_tool_output(manifest, output)

  defp context_entries(context_package_id) do
    ContextEntry
    |> Ash.Query.filter(context_package_id == ^context_package_id)
    |> Ash.Query.sort(ordinal: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp read_requests(execution_id) do
    ToolRequest
    |> Ash.Query.filter(
      execution_id == ^execution_id and state == "succeeded" and
        tool_key in ["repository.read", "openspec.read"]
    )
    |> Ash.Query.sort(requested_at: :asc, id: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp model_review_request(execution_id) do
    ModelRequest
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == "model:review")
    |> Ash.read_one!(authorize?: false)
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

  defp fetch_step(step_key) do
    case Enum.find(@steps, &(&1.key == step_key)) do
      nil -> {:error, :invalid_openspec_review_step}
      step -> {:ok, step}
    end
  end

  defp next_step(step_key) do
    @steps
    |> Enum.drop_while(&(&1.key != step_key))
    |> Enum.at(1)
  end

  defp step_enqueuer do
    Application.get_env(:office_graph, :agent_runtime_step_enqueuer, Oban)
  end

  defp completion_failure_code(:agent_step_continuation_failed),
    do: "agent_step_continuation_failed"

  defp completion_failure_code({:agent_output_kind_not_allowed, _output_kind}),
    do: "agent_output_kind_not_allowed"

  defp completion_failure_code(_reason), do: "agent_output_routing_failed"

  defp failure_code({:terminal, code}), do: failure_code(code)
  defp failure_code({:error, reason}), do: failure_code(reason)
  defp failure_code(code), do: DurableStepExecutor.safe_code(code, "openspec_review_step_failed")
end
