defmodule OfficeGraph.AgentRuntime.ExecutionWorkerTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Operations}
  alias OfficeGraph.AgentRuntime.ExecutionWorker

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ContextExpansionRequest,
    ModelRequest
  }

  alias OfficeGraph.DurableDelivery.DomainEvent
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
    assert Repo.aggregate(ModelRequest, :count) == 0

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
    assert Repo.aggregate(ModelRequest, :count) == 1
  end

  test "completed step replay does not repeat effects or state transitions" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    completed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
    event_count = Repo.aggregate(DomainEvent, :count)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3})
    replayed = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    assert replayed.state_version == completed.state_version
    assert replayed.attempt_count == completed.attempt_count
    assert Repo.aggregate(ModelRequest, :count) == 1
    assert Repo.aggregate(DomainEvent, :count) == event_count
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

    assert Repo.aggregate(ModelRequest, :count) == 0

    assert [event] =
             DomainEvent
             |> Ash.Query.filter(event_kind == "agent_execution.cancelled")
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
               operation_id == ^operation.id and event_kind == "agent_execution.cancelled"
             )
             |> Ash.read!(authorize?: false)
             |> length()
  end

  test "cancelling a running step signals the active adapter and preserves cancellation" do
    original_registry = Application.fetch_env!(:office_graph, :agent_runtime_adapters)
    registry = Map.new(original_registry)
    coordinator = start_supervised!({Agent, fn -> %{} end})

    Application.put_env(:office_graph, :execution_worker_test_coordinator, coordinator)
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    Application.put_env(:office_graph, :agent_runtime_adapters, %{
      models: %{"deterministic" => BlockingModel},
      tools: registry.tools
    })

    on_exit(fn ->
      Application.put_env(:office_graph, :agent_runtime_adapters, original_registry)
      Application.delete_env(:office_graph, :execution_worker_test_coordinator)
      Application.delete_env(:office_graph, :execution_worker_test_pid)
    end)

    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    worker = Task.async(fn -> ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3}) end)

    assert_receive {:blocking_model_started, request_id}, 1_000

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
    assert {:cancel, "cancelled"} = Task.await(worker, 1_000)

    persisted = Ash.get!(AgentExecution, cancelled.execution.id, authorize?: false)
    request = Ash.get!(ModelRequest, request_id, authorize?: false)

    assert persisted.state == "cancelled"
    assert persisted.failure_code == "cancelled_by_operator"
    assert request.state == "cancelled"
    assert request.failure_code == "cancelled_by_operator"
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
    assert Repo.aggregate(ModelRequest, :count) == 0

    assert 1 ==
             DomainEvent
             |> Ash.Query.filter(event_kind == "agent_execution.waiting_approval")
             |> Ash.read!(authorize?: false)
             |> length()
  end

  test "expansion-required context persists waiting context before adapter dispatch" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
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
    assert Repo.aggregate(ModelRequest, :count) == 0
  end

  test "context expansion fails closed when the invocation did not capture its capability" do
    context = AgentRuntimeSupport.invocation_fixture()

    invoked =
      AgentRuntimeSupport.invoke_human(context, %{
        idempotency_key: "agent-without-expansion-#{context.suffix}",
        requested_capabilities: ["agent.model.generate", "proposal.create", "repository.read"]
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
    assert Repo.aggregate(ContextExpansionRequest, :count) == 0
    assert Repo.aggregate(ModelRequest, :count) == 0
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
    assert Repo.aggregate(ModelRequest, :count) == 0

    assert [event] =
             DomainEvent
             |> Ash.Query.filter(event_kind == "agent_execution.failed")
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
    assert Repo.aggregate(ModelRequest, :count) == 0
  end

  test "concurrent duplicate dispatch has one lease owner and one durable effect" do
    original_registry = Application.fetch_env!(:office_graph, :agent_runtime_adapters)
    registry = Map.new(original_registry)
    coordinator = start_supervised!({Agent, fn -> %{} end})

    Application.put_env(:office_graph, :execution_worker_test_coordinator, coordinator)
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    Application.put_env(:office_graph, :agent_runtime_adapters, %{
      models: %{"deterministic" => BlockingModel},
      tools: registry.tools
    })

    on_exit(fn ->
      Application.put_env(:office_graph, :agent_runtime_adapters, original_registry)
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
    assert Repo.aggregate(ModelRequest, :count) == 1
    assert Repo.aggregate(DomainEvent, :count) == 2
  end

  test "worker restart reclaims an expired persisted request with the same step identity" do
    original_registry = Application.fetch_env!(:office_graph, :agent_runtime_adapters)
    registry = Map.new(original_registry)
    coordinator = start_supervised!({Agent, fn -> %{} end})

    Application.put_env(:office_graph, :execution_worker_test_coordinator, coordinator)
    Application.put_env(:office_graph, :execution_worker_test_pid, self())

    Application.put_env(:office_graph, :agent_runtime_adapters, %{
      models: %{"deterministic" => BlockingModel},
      tools: registry.tools
    })

    on_exit(fn ->
      Application.put_env(:office_graph, :agent_runtime_adapters, original_registry)
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
    assert Repo.aggregate(ModelRequest, :count) == 1
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
end
