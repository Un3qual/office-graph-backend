defmodule OfficeGraph.AgentRuntime.ExecutionWorkerTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Operations}
  alias OfficeGraph.AgentRuntime.ExecutionWorker

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ApprovalRequest,
    ContextExpansionRequest,
    ModelRequest
  }

  alias OfficeGraph.DurableDelivery.DomainEvent
  alias OfficeGraph.Integrations.IntegrationCredential
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  require Ash.Query

  import OfficeGraph.SessionCaseHelpers

  defmodule BlockingModel do
    @behaviour OfficeGraph.AgentRuntime.ModelAdapter

    alias OfficeGraph.AgentRuntime.Adapters.DeterministicModel

    @impl true
    def manifest, do: DeterministicModel.manifest()

    @impl true
    def invoke(input) do
      coordinator = Application.fetch_env!(:office_graph, :execution_worker_test_coordinator)
      test_pid = Application.fetch_env!(:office_graph, :execution_worker_test_pid)
      worker_pid = self()
      Agent.update(coordinator, &Map.put(&1, input.request_id, worker_pid))
      send(test_pid, {:blocking_model_started, input.request_id})

      receive do
        {:cancel_adapter_request, request_id} when request_id == input.request_id ->
          {:error, {:cancelled, :cancelled}}

        {:release_adapter_request, request_id} when request_id == input.request_id ->
          DeterministicModel.invoke(input)
      after
        500 -> {:error, {:terminal, :blocking_model_not_cancelled}}
      end
    end

    @impl true
    def cancel(request_id) do
      coordinator = Application.fetch_env!(:office_graph, :execution_worker_test_coordinator)
      test_pid = Application.fetch_env!(:office_graph, :execution_worker_test_pid)

      case Agent.get(coordinator, &Map.get(&1, request_id)) do
        nil -> {:error, :not_found}
        worker_pid -> send(worker_pid, {:cancel_adapter_request, request_id})
      end

      send(test_pid, {:blocking_model_cancelled, request_id})
      :ok
    end
  end

  defmodule StorageUnavailableRevalidator do
    @moduledoc false

    def revalidate_step(_execution_id, _opts),
      do: {:error, :integration_storage_unavailable}
  end

  defmodule StorageUnavailableOutputRouter do
    @moduledoc false

    def route!(_operation, _execution, _context_package, _step_key, _output) do
      raise Ash.Error.Unknown, errors: []
    end
  end

  defmodule RotatedModel do
    @behaviour OfficeGraph.AgentRuntime.ModelAdapter

    alias OfficeGraph.AgentRuntime.Adapters.DeterministicModel

    @impl true
    def manifest, do: %{DeterministicModel.manifest() | key: "rotated"}

    @impl true
    def invoke(input) do
      send(Application.fetch_env!(:office_graph, :execution_worker_test_pid), {
        :rotated_model_invoked,
        input.request_id
      })

      DeterministicModel.invoke(%{input | adapter_key: "deterministic"})
    end

    @impl true
    def cancel(request_id) do
      send(Application.fetch_env!(:office_graph, :execution_worker_test_pid), {
        :rotated_model_cancelled,
        request_id
      })

      :ok
    end
  end

  defmodule VersionTwoModel do
    @behaviour OfficeGraph.AgentRuntime.ModelAdapter

    alias OfficeGraph.AgentRuntime.Adapters.DeterministicModel

    @impl true
    def manifest, do: %{DeterministicModel.manifest() | version: "2"}

    @impl true
    def invoke(input) do
      send(Application.fetch_env!(:office_graph, :execution_worker_test_pid), {
        :version_two_model_invoked,
        input.request_id
      })

      DeterministicModel.invoke(%{input | adapter_version: "1"})
    end

    @impl true
    def cancel(_request_id), do: :ok
  end

  defmodule CredentialedModel do
    @behaviour OfficeGraph.AgentRuntime.ModelAdapter

    alias OfficeGraph.AgentRuntime.Adapters.DeterministicModel

    @impl true
    def manifest do
      %{
        DeterministicModel.manifest()
        | key: "credentialed",
          credential_kinds: [:secret_reference]
      }
    end

    @impl true
    def invoke(input) do
      send(Application.fetch_env!(:office_graph, :execution_worker_test_pid), {
        :credentialed_model_invoked,
        input.request_id
      })

      {:error, {:terminal, :unexpected_credentialed_dispatch}}
    end

    @impl true
    def cancel(_request_id), do: :ok
  end

  defmodule ManifestViolatingModel do
    @behaviour OfficeGraph.AgentRuntime.ModelAdapter

    alias OfficeGraph.AgentRuntime.Adapters.{DeterministicModel, DeterministicRuntime}
    alias OfficeGraph.AgentRuntime.ModelOutput

    @impl true
    def manifest do
      %{
        DeterministicModel.manifest()
        | key: "manifest-violating",
          output_schema: DeterministicRuntime.output_schema([:finding]),
          output_classifications: [:finding]
      }
    end

    @impl true
    def invoke(_input) do
      {:ok,
       %ModelOutput{
         classification: :proposal,
         safe_summary: "A globally valid but manifest-disallowed proposal",
         structured_content: %{"proposal" => %{"intent" => "follow_up"}}
       }}
    end

    @impl true
    def cancel(_request_id), do: :ok
  end

  test "invocation enqueues one unique durable model step and replay does not duplicate it" do
    context = AgentRuntimeSupport.invocation_fixture()

    first = AgentRuntimeSupport.invoke_human(context)
    replay = AgentRuntimeSupport.invoke_human(context)

    assert replay.execution.id == first.execution.id

    assert [%Oban.Job{} = job] = execution_jobs(first.execution.id)
    assert job.worker == inspect(ExecutionWorker)
    assert job.queue == "agents"

    assert job.args == %{
             "execution_id" => first.execution.id,
             "fixture_id" => "proposal",
             "operation_id" => job.args["operation_id"],
             "organization_id" => context.bootstrap.organization.id,
             "step_key" => "model:review",
             "workspace_id" => context.bootstrap.workspace.id
           }

    assert {:ok, step_operation} = Operations.read_operation(job.args["operation_id"])
    assert step_operation.operation_kind == "system"
    assert step_operation.action == "agent.runtime.execute"
    assert step_operation.subject_kind == "agent_execution"
    assert step_operation.subject_id == first.execution.id
  end

  test "a durable model step records running and completed state before finishing the job" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    request = Ash.read_one!(ModelRequest, authorize?: false)

    assert execution.state == "completed"
    assert execution.state_version == 3
    assert execution.current_step_key == "model:review"
    assert execution.attempt_count == 1
    assert is_nil(execution.failure_code)
    assert is_nil(execution.lease_token)
    assert is_nil(execution.lease_expires_at)
    assert %DateTime{} = execution.started_at
    assert %DateTime{} = execution.completed_at

    assert request.execution_id == execution.id
    assert request.state == "succeeded"
    assert request.step_key == "model:review"
    assert request.output_classification == "proposal"
    assert is_binary(request.input_hash)
    assert is_binary(request.output_hash)
    refute Map.has_key?(Map.from_struct(request), :raw_input)
    refute Map.has_key?(Map.from_struct(request), :raw_output)

    assert ["agent_execution.completed", "agent_execution.running"] ==
             DomainEvent
             |> Ash.Query.filter(subject_id == ^execution.id)
             |> Ash.read!(authorize?: false)
             |> Enum.map(& &1.event_kind)
             |> Enum.sort()

    assert Ash.get!(OfficeGraph.Runs.Run, context.run.id, authorize?: false).state ==
             context.run.state
  end

  test "an active lease prevents duplicate dispatch and an expired lease is recoverable" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    leased =
      invoked.execution
      |> Ash.Changeset.for_update(:transition, %{
        state: "running",
        current_step_key: "model:review",
        attempt_count: 1,
        lease_token: Ecto.UUID.generate(),
        lease_expires_at: DateTime.add(DateTime.utc_now(), 30, :second),
        started_at: DateTime.utc_now()
      })
      |> Ash.update!(authorize?: false)

    assert {:snooze, delay} = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    assert delay in 1..30
    assert Ash.get!(AgentExecution, leased.id, authorize?: false).state == "running"
    assert execution_record_count(ModelRequest, leased.id) == 0

    leased
    |> Ash.Changeset.for_update(:transition, %{
      state: "running",
      lease_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
    })
    |> Ash.update!(authorize?: false)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3})

    recovered = Ash.get!(AgentExecution, leased.id, authorize?: false)
    assert recovered.state == "completed"
    assert recovered.attempt_count == 2
    assert execution_record_count(ModelRequest, leased.id) == 1
  end

  test "completed step replay does not repeat effects or state transitions" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    completed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    event_count = execution_event_count(invoked.execution.id)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3})
    replayed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    assert replayed.state_version == completed.state_version
    assert replayed.attempt_count == completed.attempt_count
    assert execution_record_count(ModelRequest, invoked.execution.id) == 1
    assert execution_event_count(invoked.execution.id) == event_count
  end

  test "retryable failures schedule bounded retries and exhaust into one safe terminal result" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    retry_job = %{job | args: Map.put(job.args, "fixture_id", "retryable"), max_attempts: 3}

    assert {:snooze, 1} = ExecutionWorker.perform(%{retry_job | attempt: 1})
    first_retry = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert first_retry.state == "retry_scheduled"
    assert first_retry.attempt_count == 1
    assert first_retry.failure_code == "provider_unavailable"
    assert Ash.read_one!(ModelRequest, authorize?: false).state == "retry_scheduled"

    assert {:snooze, 1} = ExecutionWorker.perform(%{retry_job | attempt: 2})
    second_retry = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert second_retry.state == "retry_scheduled"
    assert second_retry.attempt_count == 2

    assert {:cancel, "attempts_exhausted"} =
             ExecutionWorker.perform(%{retry_job | attempt: 3})

    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    request = Ash.read_one!(ModelRequest, authorize?: false)
    assert failed.state == "failed"
    assert failed.attempt_count == 3
    assert failed.failure_code == "attempts_exhausted"
    assert request.state == "failed"
    assert request.failure_code == "attempts_exhausted"
    refute request.failure_code =~ "provider"
  end

  test "terminal and malformed adapter results fail without retrying or retaining raw errors" do
    for {fixture_id, failure_code} <- [
          {"terminal", "invalid_request"},
          {"malformed", "malformed_model_output"}
        ] do
      context = AgentRuntimeSupport.invocation_fixture()
      invoked = AgentRuntimeSupport.invoke_human(context)
      [job] = execution_jobs(invoked.execution.id)
      terminal_job = %{job | args: Map.put(job.args, "fixture_id", fixture_id)}

      assert {:cancel, ^failure_code} =
               ExecutionWorker.perform(%{terminal_job | attempt: 1, max_attempts: 3})

      execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

      request =
        ModelRequest
        |> Ash.Query.filter(execution_id == ^execution.id)
        |> Ash.read_one!(authorize?: false)

      assert execution.state == "failed"
      assert execution.failure_code == failure_code
      assert execution.attempt_count == 1
      assert request.state == "failed"
      assert request.failure_code == failure_code
      refute Map.has_key?(Map.from_struct(request), :raw_error)
    end
  end

  test "worker rejects globally valid output that violates the selected adapter manifest" do
    configure_adapter_registry(fn registry ->
      %{
        models: Map.put(registry.models, "manifest-violating", ManifestViolatingModel),
        tools: registry.tools
      }
    end)

    context = AgentRuntimeSupport.invocation_fixture()

    Repo.query!("UPDATE agent_definitions SET model_adapter_key = $1 WHERE id = $2", [
      "manifest-violating",
      Ecto.UUID.dump!(context.definition.id)
    ])

    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    assert {:cancel, "malformed_model_output"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    request = Ash.read_one!(ModelRequest, authorize?: false)

    assert execution.state == "failed"
    assert execution.failure_code == "malformed_model_output"
    assert request.state == "failed"
    assert request.failure_code == "malformed_model_output"
    assert execution_record_count(ProposedGraphChange, invoked.execution.id) == 0
  end

  test "output routing rejection terminalizes the claimed request and execution" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    Repo.query!(
      "UPDATE agent_definitions SET allowed_output_kinds = ARRAY['message']::text[] WHERE id = $1",
      [Ecto.UUID.dump!(context.definition.id)]
    )

    assert {:cancel, "agent_output_kind_not_allowed"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    request = Ash.read_one!(ModelRequest, authorize?: false)

    assert execution.state == "failed"
    assert execution.failure_code == "agent_output_kind_not_allowed"
    assert is_nil(execution.lease_token)
    assert is_nil(execution.lease_expires_at)
    assert request.state == "failed"
    assert request.failure_code == "agent_output_kind_not_allowed"
  end

  test "storage-unavailable output routing schedules a retry" do
    configured = Application.get_env(:office_graph, :agent_runtime_output_router)

    Application.put_env(
      :office_graph,
      :agent_runtime_output_router,
      StorageUnavailableOutputRouter
    )

    on_exit(fn ->
      if is_nil(configured) do
        Application.delete_env(:office_graph, :agent_runtime_output_router)
      else
        Application.put_env(:office_graph, :agent_runtime_output_router, configured)
      end
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    assert {:snooze, 1} = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    request = Ash.read_one!(ModelRequest, authorize?: false)

    assert execution.state == "retry_scheduled"
    assert execution.failure_code == "integration_storage_unavailable"
    assert request.state == "retry_scheduled"
    assert request.failure_code == "integration_storage_unavailable"
  end

  test "missing configured adapter terminalizes queued execution instead of stranding it" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    configure_adapter_registry(fn registry ->
      %{
        models: Map.delete(registry.models, "deterministic"),
        tools: registry.tools
      }
    end)

    assert {:cancel, "agent_adapter_unavailable"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert execution.state == "failed"
    assert execution.failure_code == "agent_adapter_unavailable"
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0
  end

  test "transient authority storage failure retries without recording false revocation" do
    configured = Application.get_env(:office_graph, :agent_runtime_revalidator)

    Application.put_env(
      :office_graph,
      :agent_runtime_revalidator,
      StorageUnavailableRevalidator
    )

    on_exit(fn ->
      if is_nil(configured) do
        Application.delete_env(:office_graph, :agent_runtime_revalidator)
      else
        Application.put_env(:office_graph, :agent_runtime_revalidator, configured)
      end
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    assert {:snooze, 1} = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    queued = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert queued.state == "queued"
    assert queued.attempt_count == 0
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0

    Application.delete_env(:office_graph, :agent_runtime_revalidator)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3})
    assert Ash.get!(AgentExecution, invoked.execution.id, authorize?: false).state == "completed"
  end

  test "model request provenance retains the credential captured by the authority snapshot" do
    context = AgentRuntimeSupport.invocation_fixture()
    original_credential = create_model_credential!(context, "original")
    rotated_credential = create_model_credential!(context, "rotated")

    Repo.query!("UPDATE agent_definitions SET model_credential_id = $1 WHERE id = $2", [
      Ecto.UUID.dump!(original_credential.id),
      Ecto.UUID.dump!(context.definition.id)
    ])

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        idempotency_key: "snapshotted-model-credential-#{context.suffix}"
      })

    assert invoked.authority_snapshot.credential_ids == [original_credential.id]

    Repo.query!("UPDATE agent_definitions SET model_credential_id = $1 WHERE id = $2", [
      Ecto.UUID.dump!(rotated_credential.id),
      Ecto.UUID.dump!(context.definition.id)
    ])

    [job] = execution_jobs(invoked.execution.id)
    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    request = Ash.read_one!(ModelRequest, authorize?: false)
    assert request.credential_id == original_credential.id
    refute request.credential_id == rotated_credential.id
  end

  test "execution uses the adapter identity captured at invocation after definition rotation" do
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    configure_adapter_registry(fn registry ->
      %{
        models: Map.put(registry.models, "rotated", RotatedModel),
        tools: registry.tools
      }
    end)

    on_exit(fn ->
      Application.delete_env(:office_graph, :execution_worker_test_pid)
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)

    Repo.query!("UPDATE agent_definitions SET model_adapter_key = 'rotated' WHERE id = $1", [
      Ecto.UUID.dump!(context.definition.id)
    ])

    [job] = execution_jobs(invoked.execution.id)
    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    refute_receive {:rotated_model_invoked, _request_id}

    request = Ash.read_one!(ModelRequest, authorize?: false)
    assert request.adapter_key == "deterministic"
    assert request.adapter_version == "1"
    assert invoked.authority_snapshot.model_adapter_key == "deterministic"
    assert invoked.authority_snapshot.model_adapter_version == "1"
  end

  test "execution fails closed when the captured adapter version is no longer registered" do
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:office_graph, :execution_worker_test_pid)
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)

    configure_adapter_registry(fn registry ->
      %{
        models: Map.put(registry.models, "deterministic", VersionTwoModel),
        tools: registry.tools
      }
    end)

    [job] = execution_jobs(invoked.execution.id)

    assert {:cancel, "agent_adapter_unavailable"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    refute_receive {:version_two_model_invoked, _request_id}
    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "agent_adapter_unavailable"
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0
  end

  test "credentialed adapters require matching credential metadata captured by authority" do
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    configure_adapter_registry(fn registry ->
      %{
        models: Map.put(registry.models, "credentialed", CredentialedModel),
        tools: registry.tools
      }
    end)

    on_exit(fn ->
      Application.delete_env(:office_graph, :execution_worker_test_pid)
    end)

    context = AgentRuntimeSupport.invocation_fixture()

    Repo.query!("UPDATE agent_definitions SET model_adapter_key = 'credentialed' WHERE id = $1", [
      Ecto.UUID.dump!(context.definition.id)
    ])

    invoked = AgentRuntimeSupport.invoke_human(context)
    assert invoked.authority_snapshot.credential_ids == []
    [job] = execution_jobs(invoked.execution.id)

    assert {:cancel, "missing_credential"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    refute_receive {:credentialed_model_invoked, _request_id}
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0

    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "missing_credential"
  end

  test "an authorized cancellation terminalizes queued work and prevents adapter dispatch" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    attrs = %{
      execution_id: invoked.execution.id,
      expected_state_version: invoked.execution.state_version
    }

    assert {:ok, operation} =
             Operations.start_command(
               context.session,
               :agent_cancel,
               "cancel-agent-#{context.suffix}",
               attrs
             )

    result =
      if function_exported?(AgentRuntime, :cancel_execution, 3) do
        AgentRuntime.cancel_execution(context.session, operation, attrs)
      else
        :missing_cancel_command
      end

    assert {:ok, cancelled} = result
    assert cancelled.execution.state == "cancelled"
    assert cancelled.execution.failure_code == "cancelled_by_operator"
    assert cancelled.execution.state_version == invoked.execution.state_version + 1
    assert %DateTime{} = cancelled.execution.cancelled_at
    assert is_nil(cancelled.execution.lease_token)
    assert is_nil(cancelled.model_request)

    assert {:cancel, "cancelled_by_operator"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    assert execution_record_count(ModelRequest, invoked.execution.id) == 0

    assert [event] =
             DomainEvent
             |> Ash.Query.filter(
               subject_id == ^invoked.execution.id and event_kind == "agent_execution.cancelled"
             )
             |> Ash.read!(authorize?: false)

    assert event.operation_id == operation.id
    assert event.subject_id == invoked.execution.id
    assert event.subject_version == cancelled.execution.state_version
  end

  test "a lost cancellation response replays the result for the same operation" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)

    attrs = %{
      execution_id: invoked.execution.id,
      expected_state_version: invoked.execution.state_version
    }

    assert {:ok, operation} =
             Operations.start_command(
               context.session,
               :agent_cancel,
               "replay-agent-cancel-#{context.suffix}",
               attrs
             )

    assert {:ok, first} = AgentRuntime.cancel_execution(context.session, operation, attrs)
    assert {:ok, replay} = AgentRuntime.cancel_execution(context.session, operation, attrs)

    assert replay.execution.id == first.execution.id
    assert replay.execution.state_version == first.execution.state_version
    assert replay.model_request == first.model_request

    assert 1 ==
             DomainEvent
             |> Ash.Query.filter(
               subject_id == ^invoked.execution.id and operation_id == ^operation.id and
                 event_kind == "agent_execution.cancelled"
             )
             |> Ash.read!(authorize?: false)
             |> length()
  end

  test "cancelling a running step signals the active adapter and preserves cancellation" do
    coordinator = start_supervised!({Agent, fn -> %{} end})

    Application.put_env(:office_graph, :execution_worker_test_coordinator, coordinator)
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    configure_adapter_registry(fn registry ->
      %{
        models: %{"deterministic" => BlockingModel, "rotated" => RotatedModel},
        tools: registry.tools
      }
    end)

    on_exit(fn ->
      Application.delete_env(:office_graph, :execution_worker_test_coordinator)
      Application.delete_env(:office_graph, :execution_worker_test_pid)
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    worker = Task.async(fn -> ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3}) end)

    assert_receive {:blocking_model_started, request_id}, 1_000

    Repo.query!("UPDATE agent_definitions SET model_adapter_key = 'rotated' WHERE id = $1", [
      Ecto.UUID.dump!(context.definition.id)
    ])

    running = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    attrs = %{
      execution_id: running.id,
      expected_state_version: running.state_version
    }

    assert {:ok, operation} =
             Operations.start_command(
               context.session,
               :agent_cancel,
               "cancel-running-agent-#{context.suffix}",
               attrs
             )

    assert {:ok, cancelled} = AgentRuntime.cancel_execution(context.session, operation, attrs)
    assert_receive {:blocking_model_cancelled, ^request_id}, 1_000
    refute_receive {:rotated_model_cancelled, ^request_id}

    assert {:ok, replayed} = AgentRuntime.cancel_execution(context.session, operation, attrs)
    assert replayed.replayed?
    assert_receive {:blocking_model_cancelled, ^request_id}, 1_000
    refute_receive {:rotated_model_cancelled, ^request_id}

    assert {:cancel, "cancelled"} = Task.await(worker, 1_000)

    persisted = Ash.get!(AgentExecution, cancelled.execution.id, authorize?: false)
    request = Ash.get!(ModelRequest, request_id, authorize?: false)

    assert persisted.state == "cancelled"
    assert persisted.failure_code == "cancelled_by_operator"
    assert request.state == "cancelled"
    assert request.failure_code == "cancelled_by_operator"
  end

  test "cancelling waiting executions retires their exact pending gates" do
    original_approval = Application.get_env(:office_graph, :deterministic_model_approval_required)
    Application.put_env(:office_graph, :deterministic_model_approval_required, true)

    on_exit(fn ->
      if is_nil(original_approval) do
        Application.delete_env(:office_graph, :deterministic_model_approval_required)
      else
        Application.put_env(
          :office_graph,
          :deterministic_model_approval_required,
          original_approval
        )
      end
    end)

    approval_context = AgentRuntimeSupport.invocation_fixture()
    approval_invocation = AgentRuntimeSupport.invoke_human(approval_context)
    [approval_job] = execution_jobs(approval_invocation.execution.id)
    assert :ok = ExecutionWorker.perform(%{approval_job | attempt: 1, max_attempts: 3})

    approval =
      ApprovalRequest
      |> Ash.Query.filter(
        execution_id == ^approval_invocation.execution.id and state == "pending"
      )
      |> Ash.read_one!(authorize?: false)

    cancelled_approval = cancel_execution!(approval_context, approval_invocation.execution.id)
    retired_approval = Ash.get!(ApprovalRequest, approval.id, authorize?: false)

    assert retired_approval.state == "cancelled"
    assert retired_approval.version == approval.version + 1
    assert retired_approval.resolution_operation_id == cancelled_approval.operation.id
    assert retired_approval.resolved_by_principal_id == approval_context.session.principal_id
    assert retired_approval.resolution_reason == "execution_cancelled"
    assert %DateTime{} = retired_approval.resolved_at

    Application.put_env(:office_graph, :deterministic_model_approval_required, false)
    expansion_context = AgentRuntimeSupport.invocation_fixture()
    allow_generic_context_expansion!(expansion_context)

    expansion_invocation =
      AgentRuntimeSupport.invoke_human(expansion_context, %{
        requested_capabilities: [
          "agent.model.generate",
          "agent.tool.read",
          "evidence.suggest",
          "proposal.create"
        ]
      })

    [expansion_job] = execution_jobs(expansion_invocation.execution.id)

    Repo.query!(
      "UPDATE agent_context_entries SET posture = 'expansion_required' WHERE context_package_id = $1 AND ordinal = 0",
      [Ecto.UUID.dump!(expansion_invocation.context_package.id)]
    )

    assert :ok = ExecutionWorker.perform(%{expansion_job | attempt: 1, max_attempts: 3})

    expansion =
      ContextExpansionRequest
      |> Ash.Query.filter(
        execution_id == ^expansion_invocation.execution.id and state == "pending"
      )
      |> Ash.read_one!(authorize?: false)

    cancelled_expansion = cancel_execution!(expansion_context, expansion_invocation.execution.id)
    retired_expansion = Ash.get!(ContextExpansionRequest, expansion.id, authorize?: false)

    assert retired_expansion.state == "cancelled"
    assert retired_expansion.version == expansion.version + 1
    assert retired_expansion.resolution_operation_id == cancelled_expansion.operation.id
    assert retired_expansion.resolved_by_principal_id == expansion_context.session.principal_id
    assert retired_expansion.resolution_reason == "execution_cancelled"
    assert %DateTime{} = retired_expansion.resolved_at
  end

  test "approval-gated adapters persist waiting approval without consuming an attempt" do
    original = Application.get_env(:office_graph, :deterministic_model_approval_required)
    Application.put_env(:office_graph, :deterministic_model_approval_required, true)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:office_graph, :deterministic_model_approval_required)
      else
        Application.put_env(:office_graph, :deterministic_model_approval_required, original)
      end
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    assert :ok = ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3})

    waiting = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert waiting.state == "waiting_approval"
    assert waiting.current_step_key == "model:review"
    assert waiting.attempt_count == 0
    assert is_nil(waiting.lease_token)
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0

    assert 1 ==
             DomainEvent
             |> Ash.Query.filter(
               subject_id == ^invoked.execution.id and
                 event_kind == "agent_execution.waiting_approval"
             )
             |> Ash.read!(authorize?: false)
             |> length()
  end

  test "missing manifest authority fails before an impossible approval gate is opened" do
    original = Application.get_env(:office_graph, :deterministic_model_approval_required)
    Application.put_env(:office_graph, :deterministic_model_approval_required, true)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:office_graph, :deterministic_model_approval_required)
      else
        Application.put_env(:office_graph, :deterministic_model_approval_required, original)
      end
    end)

    context = AgentRuntimeSupport.invocation_fixture()

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        idempotency_key: "approval-without-model-authority-#{context.suffix}",
        requested_capabilities: ["evidence.suggest", "proposal.create"]
      })

    [job] = execution_jobs(invoked.execution.id)

    assert {:cancel, "missing_capability"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "missing_capability"
    assert execution_record_count(ApprovalRequest, invoked.execution.id) == 0
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0
  end

  test "expansion-required context persists waiting context before adapter dispatch" do
    context = AgentRuntimeSupport.invocation_fixture()
    allow_generic_context_expansion!(context)

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        requested_capabilities: [
          "agent.model.generate",
          "agent.tool.read",
          "evidence.suggest",
          "proposal.create"
        ]
      })

    [job] = execution_jobs(invoked.execution.id)

    Repo.query!(
      """
      UPDATE agent_context_entries
      SET posture = 'expansion_required'
      WHERE context_package_id = $1
        AND ordinal = (
          SELECT MIN(ordinal)
          FROM agent_context_entries
          WHERE context_package_id = $1
        )
      """,
      [Ecto.UUID.dump!(invoked.context_package.id)]
    )

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    waiting = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert waiting.state == "waiting_context"
    assert waiting.current_step_key == "model:review"
    assert waiting.attempt_count == 0
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0
  end

  test "context expansion fails closed when the invocation did not capture its capability" do
    context = AgentRuntimeSupport.invocation_fixture()

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        idempotency_key: "agent-without-expansion-#{context.suffix}",
        requested_capabilities: ["agent.model.generate", "evidence.suggest", "proposal.create"]
      })

    [job] = execution_jobs(invoked.execution.id)
    target = Enum.min_by(invoked.context_entries, & &1.ordinal)

    OfficeGraph.Repo.query!(
      "UPDATE agent_context_entries SET posture = 'expansion_required' WHERE id = $1",
      [Ecto.UUID.dump!(target.id)]
    )

    assert {:cancel, "agent_context_expansion_not_authorized"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "agent_context_expansion_not_authorized"
    assert execution_record_count(ContextExpansionRequest, invoked.execution.id) == 0
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0
  end

  test "mutable authority is revalidated before a step and revocation fails it closed" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    context.binding
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{lifecycle_state: "disabled"})
    |> Ash.update!(authorize?: false)

    assert {:cancel, "agent_authority_revoked"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "agent_authority_revoked"
    assert failed.attempt_count == 0
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0

    assert [event] =
             DomainEvent
             |> Ash.Query.filter(
               subject_id == ^failed.id and event_kind == "agent_execution.failed"
             )
             |> Ash.read!(authorize?: false)

    assert event.subject_id == failed.id
    assert event.subject_version == failed.state_version
    assert event.operation_kind == "system"
  end

  test "principal revocation still records terminal state through the predeclared step operation" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    Repo.query!("UPDATE principals SET status = 'inactive', updated_at = now() WHERE id = $1", [
      Ecto.UUID.dump!(context.agent_principal.id)
    ])

    assert {:cancel, "agent_authority_revoked"} =
             ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    failed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "agent_authority_revoked"
    assert failed.attempt_count == 0
    assert execution_record_count(ModelRequest, invoked.execution.id) == 0
  end

  test "concurrent duplicate dispatch has one lease owner and one durable effect" do
    coordinator = start_supervised!({Agent, fn -> %{} end})

    Application.put_env(:office_graph, :execution_worker_test_coordinator, coordinator)
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    configure_adapter_registry(fn registry ->
      %{
        models: %{"deterministic" => BlockingModel},
        tools: registry.tools
      }
    end)

    on_exit(fn ->
      Application.delete_env(:office_graph, :execution_worker_test_coordinator)
      Application.delete_env(:office_graph, :execution_worker_test_pid)
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    first = Task.async(fn -> ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3}) end)

    assert_receive {:blocking_model_started, request_id}, 1_000

    assert {:snooze, delay} = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    assert delay in 1..30
    refute_receive {:blocking_model_started, _duplicate_request_id}, 50

    owner = Agent.get(coordinator, &Map.fetch!(&1, request_id))
    send(owner, {:release_adapter_request, request_id})
    assert :ok = Task.await(first, 1_000)

    completed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    assert completed.state == "completed"
    assert completed.attempt_count == 1
    assert execution_record_count(ModelRequest, invoked.execution.id) == 1
    assert execution_event_count(invoked.execution.id) == 2
  end

  test "worker restart reclaims an expired persisted request with the same step identity" do
    coordinator = start_supervised!({Agent, fn -> %{} end})

    Application.put_env(:office_graph, :execution_worker_test_coordinator, coordinator)
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    original_registry =
      configure_adapter_registry(fn registry ->
        %{
          models: %{"deterministic" => BlockingModel},
          tools: registry.tools
        }
      end)

    on_exit(fn ->
      Application.delete_env(:office_graph, :execution_worker_test_coordinator)
      Application.delete_env(:office_graph, :execution_worker_test_pid)
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    crashed = Task.async(fn -> ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3}) end)

    assert_receive {:blocking_model_started, request_id}, 1_000
    Task.shutdown(crashed, :brutal_kill)

    running = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    request = Ash.get!(ModelRequest, request_id, authorize?: false)
    assert running.state == "running"
    assert running.attempt_count == 1
    assert request.state == "running"

    running
    |> Ash.Changeset.for_update(:transition, %{
      state: "running",
      lease_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
    })
    |> Ash.update!(authorize?: false)

    Application.put_env(:office_graph, :agent_runtime_adapters, original_registry)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3})

    recovered = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    recovered_request = Ash.get!(ModelRequest, request_id, authorize?: false)
    assert recovered.state == "completed"
    assert recovered.attempt_count == 2
    assert recovered_request.state == "succeeded"
    assert execution_record_count(ModelRequest, invoked.execution.id) == 1
  end

  test "cancellation rejects missing capability and stale execution versions" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)

    denied_session =
      create_session_with_capabilities!(context.bootstrap, [], prefix: "agent-cancel-denied")

    attrs = %{
      execution_id: invoked.execution.id,
      expected_state_version: invoked.execution.state_version
    }

    assert {:ok, denied_operation} =
             Operations.start_command(
               denied_session,
               :agent_cancel,
               "denied-agent-cancel-#{context.suffix}",
               attrs
             )

    assert {:error, :forbidden} =
             AgentRuntime.cancel_execution(denied_session, denied_operation, attrs)

    stale_attrs = %{attrs | expected_state_version: invoked.execution.state_version + 1}

    assert {:ok, stale_operation} =
             Operations.start_command(
               context.session,
               :agent_cancel,
               "stale-agent-cancel-#{context.suffix}",
               stale_attrs
             )

    assert {:error, {:stale_agent_execution, execution_id, current_version}} =
             AgentRuntime.cancel_execution(context.session, stale_operation, stale_attrs)

    assert execution_id == invoked.execution.id
    assert current_version == invoked.execution.state_version
    assert Ash.get!(AgentExecution, execution_id, authorize?: false).state == "queued"
  end

  defp execution_jobs(execution_id) do
    Oban.Job
    |> where(
      [job],
      job.worker == ^inspect(ExecutionWorker) and
        fragment("?->>'execution_id'", job.args) == ^execution_id
    )
    |> Repo.all()
  end

  defp execution_record_count(resource, execution_id) do
    resource
    |> Ash.Query.filter(execution_id == ^execution_id)
    |> Ash.read!(authorize?: false)
    |> length()
  end

  defp execution_event_count(execution_id) do
    DomainEvent
    |> Ash.Query.filter(subject_id == ^execution_id)
    |> Ash.read!(authorize?: false)
    |> length()
  end

  defp allow_generic_context_expansion!(context) do
    Repo.query!(
      """
      UPDATE agent_definitions
      SET requested_capabilities = ARRAY[
            'agent.model.generate',
            'agent.tool.read',
            'evidence.suggest',
            'proposal.create'
          ]::text[],
          updated_at = now()
      WHERE id = $1
      """,
      [Ecto.UUID.dump!(context.definition.id)]
    )

    Repo.query!(
      """
      INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
      SELECT gen_random_uuid(), assignments.role_id, capabilities.id, now(), now()
      FROM role_assignments AS assignments
      JOIN capabilities ON capabilities.key = 'agent.tool.read'
      WHERE assignments.principal_id IN ($1, $2)
        AND assignments.organization_id = $3
        AND assignments.workspace_id = $4
      ON CONFLICT (role_id, capability_id) DO NOTHING
      """,
      [
        Ecto.UUID.dump!(context.agent_principal.id),
        Ecto.UUID.dump!(context.bootstrap.principal.id),
        Ecto.UUID.dump!(context.bootstrap.organization.id),
        Ecto.UUID.dump!(context.bootstrap.workspace.id)
      ]
    )
  end

  defp configure_adapter_registry(update) when is_function(update, 1) do
    original = Application.fetch_env!(:office_graph, :agent_runtime_adapters)
    registry = original |> Map.new() |> update.()

    Application.put_env(:office_graph, :agent_runtime_adapters, registry)
    on_exit(fn -> Application.put_env(:office_graph, :agent_runtime_adapters, original) end)

    original
  end

  defp create_model_credential!(context, label) do
    Ash.create!(
      IntegrationCredential,
      %{
        id: Ecto.UUID.generate(),
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.bootstrap.workspace.id,
        kind: "secret_reference",
        secret_reference: "test-secret://agent-runtime/#{label}/#{context.suffix}",
        status: "active",
        operation_id: context.binding.operation_id
      },
      action: :create,
      authorize?: false
    )
  end

  defp cancel_execution!(context, execution_id) do
    execution = Ash.get!(AgentExecution, execution_id, authorize?: false)

    attrs = %{
      execution_id: execution.id,
      expected_state_version: execution.state_version
    }

    {:ok, operation} =
      Operations.start_command(
        context.session,
        :agent_cancel,
        "cancel-waiting-agent-#{context.suffix}-#{execution.state}",
        attrs
      )

    assert {:ok, result} = AgentRuntime.cancel_execution(context.session, operation, attrs)
    %{operation: operation, result: result}
  end
end
