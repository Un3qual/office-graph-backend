defmodule OfficeGraph.AgentRuntime.ExecutionWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  alias OfficeGraph.{AgentRuntime, Operations, Repo}
  alias OfficeGraph.Integrations.IntegrationCredential

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    AdapterRegistry,
    AgentDefinition,
    AgentExecution,
    ApprovalRequest,
    AuthoritySnapshot,
    ContextEntry,
    ContextExpansionRequest,
    ContextPackage,
    DurableStepExecutor,
    GateExpiryWorker,
    ModelInput,
    ModelRequest,
    OutputRouter
  }

  alias OfficeGraph.AgentRuntime.Agents.OpenSpecReviewWorkflow

  require Ash.Query

  @initial_step_key "model:review"
  @initial_fixture_id "proposal"
  @retry_delay_seconds 1

  def prepare_initial(%AgentExecution{} = execution, %AuthoritySnapshot{} = snapshot) do
    if execution.invocation_mode == "automatic" do
      OpenSpecReviewWorkflow.prepare_initial(execution, snapshot)
    else
      with {:ok, operation} <- create_step_operation(execution, snapshot, @initial_step_key),
           {:ok, job} <-
             execution
             |> initial_args(operation.id)
             |> new()
             |> Oban.insert() do
        {:ok, %{operation: operation, job: job}}
      end
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
  def perform(%Oban.Job{args: %{"workflow_key" => "openspec-review"}} = job),
    do: OpenSpecReviewWorkflow.perform(job)

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
        DurableStepExecutor.fail_unclaimed(
          %{execution: execution, operation: operation},
          %{key: step_key},
          job,
          failure_code
        )

      {:error, _reason} ->
        DurableStepExecutor.finish_terminal_job(job, "invalid_agent_job_scope")
    end
  end

  def perform(_job), do: {:cancel, "invalid_agent_job"}

  defp perform_context(context, step_key, fixture_id, job) do
    context = Map.put(context, :credential_id, snapshotted_model_credential_id!(context.snapshot))
    step = %{key: step_key, kind: :model}

    DurableStepExecutor.perform(context, job,
      step: step,
      build_input: &model_input(&1, &1.operation, &2, step_key, fixture_id),
      preflight: &AdapterContract.validate_model_preflight(context.manifest, &1),
      before_claim: &before_model_claim(&1, &2, &3, step_key, fixture_id),
      validate_input: &AdapterContract.validate_model_input(context.manifest, &1),
      validate_output: &AdapterContract.validate_model_output(context.manifest, &1),
      invoke: &DurableStepExecutor.invoke_safely(context.adapter, &1),
      revalidate: fn runtime_context ->
        revalidate_step(
          runtime_context.execution.id,
          approval_request_id: runtime_context.approval_request_id,
          context_expansion_request_id: runtime_context.context_expansion_request_id
        )
      end,
      advance: &complete_model_step(context, step_key, &1, &2, &3, &4),
      revalidation_failure_code: fn _reason -> "agent_authority_revoked" end,
      claim_failure_code: &model_claim_failure_code/1,
      completion_failure_code: &output_routing_failure_code/1
    )
  end

  defp before_model_claim(context, execution, _input, step_key, fixture_id) do
    cond do
      context_requires_expansion?(context.context_package.id) ->
        {:return,
         wait_available_step(
           context,
           context.operation,
           execution,
           step_key,
           fixture_id,
           "waiting_context"
         )}

      context.manifest.approval_required and is_nil(context.approval_request_id) ->
        {:return,
         wait_available_step(
           context,
           context.operation,
           execution,
           step_key,
           fixture_id,
           "waiting_approval"
         )}

      true ->
        :continue
    end
  end

  defp complete_model_step(context, step_key, execution, _request, output, now) do
    OutputRouter.route!(
      context.operation,
      execution,
      context.context_package,
      step_key,
      output
    )

    DurableStepExecutor.transition!(execution, context.operation, "completed", %{
      completed_at: now,
      failure_code: nil,
      lease_token: nil,
      lease_expires_at: nil
    })
  end

  defp model_claim_failure_code(:context_expansion_not_authorized),
    do: "agent_context_expansion_not_authorized"

  defp model_claim_failure_code({:terminal, code}),
    do: DurableStepExecutor.safe_code(code, "agent_adapter_authority_invalid")

  defp model_claim_failure_code(_reason), do: "agent_step_claim_failed"

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

  defp create_step_operation(execution, snapshot, step_key) do
    DurableStepExecutor.create_step_operation(execution, snapshot, step_key)
  end

  defp validate_step_operation(operation, execution, snapshot, step_key) do
    DurableStepExecutor.validate_step_operation(operation, execution, snapshot, step_key)
  end

  defp wait_available_step(
         context,
         operation,
         execution,
         step_key,
         _fixture_id,
         waiting_state
       ) do
    waiting_request =
      prepare_waiting_request!(waiting_state, context, operation, execution, step_key)

    waiting =
      DurableStepExecutor.transition!(execution, operation, waiting_state, %{
        current_step_key: step_key,
        failure_code: nil,
        lease_token: nil,
        lease_expires_at: nil
      })

    GateExpiryWorker.enqueue!(waiting_request)

    {:waiting, waiting_state, waiting, waiting_request}
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
      credential_id: snapshotted_model_credential_id!(context.snapshot),
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
          :credential_id,
          :context_expansion_request_id,
          :sensitivity,
          :external_write,
          :state,
          :version
        ],
        &(Map.get(request, &1) == Map.get(attrs, &1))
      )

    if valid?, do: request, else: Repo.rollback(:agent_approval_request_conflict)
  end

  defp snapshotted_model_credential_id!(%AuthoritySnapshot{credential_ids: []}), do: nil

  defp snapshotted_model_credential_id!(%AuthoritySnapshot{credential_ids: [credential_id]}),
    do: credential_id

  defp snapshotted_model_credential_id!(_snapshot),
    do: Repo.rollback(:authority_snapshot_invalid)

  defp model_input(context, operation, execution, step_key, fixture_id) do
    manifest = context.manifest

    %ModelInput{
      request_id: DurableStepExecutor.existing_request_id(ModelRequest, execution.id, step_key),
      execution_id: execution.id,
      step_key: step_key,
      context_package_id: context.context_package.id,
      authority_snapshot_id: context.snapshot.id,
      operation_id: operation.id,
      adapter_key: manifest.key,
      adapter_version: manifest.version,
      idempotency_key: DurableStepExecutor.step_idempotency_key(execution.id, step_key),
      capability_keys: context.snapshot.capability_keys,
      credential_kinds: context.credential_kinds,
      sensitivity: manifest.sensitivity,
      approval_granted?: is_binary(context.approval_request_id),
      timeout_ms: manifest.timeout_ms,
      token_budget: manifest.token_budget,
      adapter_payload: %{fixture_id: fixture_id}
    }
  end

  defp context_requires_expansion?(context_package_id) do
    ContextEntry
    |> Ash.Query.filter(
      context_package_id == ^context_package_id and posture == "expansion_required"
    )
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
    |> is_struct(ContextEntry)
  end

  defp output_routing_failure_code({:agent_output_kind_not_allowed, _output_kind}),
    do: "agent_output_kind_not_allowed"

  defp output_routing_failure_code(_reason), do: "agent_output_routing_failed"

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
