defmodule OfficeGraph.AgentRuntime.ConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  require Ash.Query

  alias OfficeGraph.AgentRuntime

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ApprovalRequest,
    ContextExpansionRequest,
    ExecutionWorker,
    ModelRequest
  }

  alias OfficeGraph.TestSupport.{AgentRuntimeCleanup, AgentRuntimeSupport}

  test "separate owners converge on one binding and one invocation" do
    suffix = System.unique_integer([:positive])

    bootstrap =
      with_unboxed_connection(fn ->
        {:ok, bootstrap} =
          Foundation.bootstrap_local_owner(
            organization_name: "Agent binding race #{suffix}",
            organization_slug: "agent-binding-race-#{suffix}",
            workspace_name: "Agent binding race workspace #{suffix}",
            workspace_slug: "agent-binding-race-workspace-#{suffix}",
            owner_email: "agent-binding-race-#{suffix}@office-graph.local"
          )

        bootstrap
      end)

    register_cleanup(bootstrap)

    binding_results =
      1..2
      |> Enum.map(fn attempt ->
        fn ->
          AgentRuntime.bind_run_review_agent(bootstrap.session, %{
            idempotency_key: "agent-binding-race-#{suffix}-#{attempt}"
          })
        end
      end)
      |> run_concurrently()

    assert [binding_id] =
             binding_results
             |> Enum.map(fn {:ok, result} -> result.binding.id end)
             |> Enum.uniq()

    assert [principal_id] =
             binding_results
             |> Enum.map(fn {:ok, result} -> result.principal.id end)
             |> Enum.uniq()

    {context, request, operation} =
      with_unboxed_connection(fn ->
        context = AgentRuntimeSupport.invocation_fixture()
        request = AgentRuntimeSupport.request(context)
        {:ok, operation} = AgentRuntimeSupport.human_operation(context.session, request)
        {context, request, operation}
      end)

    register_cleanup(context.bootstrap)

    invocation_results =
      [
        fn -> AgentRuntime.invoke(context.session, operation, request) end,
        fn -> AgentRuntime.invoke(context.session, operation, request) end
      ]
      |> run_concurrently()

    assert [execution_id] =
             invocation_results
             |> Enum.map(fn {:ok, result} -> result.execution.id end)
             |> Enum.uniq()

    assert [context_package_id] =
             invocation_results
             |> Enum.map(fn {:ok, result} -> result.context_package.id end)
             |> Enum.uniq()

    assert is_binary(binding_id)
    assert is_binary(principal_id)
    assert is_binary(execution_id)
    assert is_binary(context_package_id)
  end

  test "separate owners serialize approval and context-expansion decisions" do
    approval_fixture = with_unboxed_connection(fn -> waiting_gate_fixture(:approval) end)
    register_cleanup(approval_fixture.context.bootstrap)

    approval_results =
      approval_fixture
      |> decision_funs(:approval)
      |> run_concurrently()

    assert_one_gate_winner(
      approval_results,
      approval_fixture.request,
      :stale_agent_approval
    )

    approval =
      with_unboxed_connection(fn ->
        Ash.get!(ApprovalRequest, approval_fixture.request.id, authorize?: false)
      end)

    assert approval.version == 2
    assert approval.state in ["approved", "denied"]

    expansion_fixture =
      with_unboxed_connection(fn -> waiting_gate_fixture(:context_expansion) end)

    register_cleanup(expansion_fixture.context.bootstrap)

    expansion_results =
      expansion_fixture
      |> decision_funs(:context_expansion)
      |> run_concurrently()

    assert_one_gate_winner(
      expansion_results,
      expansion_fixture.request,
      :stale_agent_context_expansion
    )

    expansion =
      with_unboxed_connection(fn ->
        Ash.get!(ContextExpansionRequest, expansion_fixture.request.id, authorize?: false)
      end)

    assert expansion.version == 2
    assert expansion.state in ["denied", "cancelled"]
  end

  test "separate owners preserve one pending request per gate step" do
    for kind <- [:approval, :context_expansion] do
      fixture = with_unboxed_connection(fn -> waiting_execution_fixture(kind) end)
      register_cleanup(fixture.context.bootstrap)

      {resource, attrs} = pending_request(fixture, kind)

      results =
        [
          fn -> create_pending_request(resource, attrs) end,
          fn -> create_pending_request(resource, attrs) end
        ]
        |> run_concurrently()

      assert 1 == Enum.count(results, &match?({:ok, _request}, &1))
      assert 1 == Enum.count(results, &match?({:error, %Ash.Error.Invalid{}}, &1))

      pending_count =
        with_unboxed_connection(fn ->
          resource
          |> Ash.Query.filter(
            execution_id == ^fixture.execution.id and
              step_key == ^fixture.step_key and
              state == "pending"
          )
          |> Ash.read!(authorize?: false)
          |> length()
        end)

      assert pending_count == 1
    end
  end

  test "separate owners serialize cancellation and duplicate lease claims" do
    {context, invoked, cancellation_operations, cancellation_attrs} =
      with_unboxed_connection(fn ->
        context = AgentRuntimeSupport.invocation_fixture()
        invoked = AgentRuntimeSupport.invoke_human(context)

        attrs = %{
          execution_id: invoked.execution.id,
          expected_state_version: invoked.execution.state_version
        }

        operations =
          for attempt <- 1..2 do
            {:ok, operation} =
              Operations.start_command(
                context.session,
                :agent_cancel,
                "agent-cancel-race-#{context.suffix}-#{attempt}",
                attrs
              )

            operation
          end

        {context, invoked, operations, attrs}
      end)

    register_cleanup(context.bootstrap)

    cancellation_results =
      cancellation_operations
      |> Enum.map(fn operation ->
        fn ->
          AgentRuntime.cancel_execution(
            context.session,
            operation,
            cancellation_attrs
          )
        end
      end)
      |> run_concurrently()

    assert 1 == Enum.count(cancellation_results, &match?({:ok, _result}, &1))

    assert 1 ==
             Enum.count(cancellation_results, fn
               {:error, {:stale_agent_execution, execution_id, actual_version}}
               when execution_id == invoked.execution.id and
                      actual_version == invoked.execution.state_version + 1 ->
                 true

               _other ->
                 false
             end)

    cancelled =
      with_unboxed_connection(fn ->
        Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)
      end)

    assert cancelled.state == "cancelled"

    {lease_execution_id, lease_job, lease_bootstrap} =
      with_unboxed_connection(fn ->
        lease_context = AgentRuntimeSupport.invocation_fixture()
        lease_invoked = AgentRuntimeSupport.invoke_human(lease_context)
        [job] = AgentRuntimeSupport.execution_jobs(lease_invoked.execution.id)

        terminal_job = %{job | args: Map.put(job.args, "fixture_id", "terminal")}

        {lease_invoked.execution.id, terminal_job, lease_context.bootstrap}
      end)

    register_cleanup(lease_bootstrap)

    lease_results =
      [
        fn -> ExecutionWorker.perform(%{lease_job | attempt: 1, max_attempts: 3}) end,
        fn -> ExecutionWorker.perform(%{lease_job | attempt: 1, max_attempts: 3}) end
      ]
      |> run_concurrently()

    assert 1 == Enum.count(lease_results, &(&1 == {:cancel, "invalid_request"}))
    assert 1 == Enum.count(lease_results, &match?({:snooze, _delay}, &1))

    {leased_execution, lease_request_count} =
      with_unboxed_connection(fn ->
        execution = Ash.get!(AgentExecution, lease_execution_id, authorize?: false)

        request_count =
          ModelRequest
          |> Ash.Query.filter(execution_id == ^lease_execution_id)
          |> Ash.count!(authorize?: false)

        {execution, request_count}
      end)

    assert leased_execution.state == "failed"
    assert leased_execution.attempt_count == 1
    assert lease_request_count == 1
  end

  test "separate owners preserve one request through retry and terminal races" do
    {retry_execution_id, retry_job, retry_bootstrap} =
      with_unboxed_connection(fn -> worker_fixture("retryable") end)

    register_cleanup(retry_bootstrap)

    retry_results =
      [
        fn -> ExecutionWorker.perform(%{retry_job | attempt: 1, max_attempts: 3}) end,
        fn -> ExecutionWorker.perform(%{retry_job | attempt: 1, max_attempts: 3}) end
      ]
      |> run_concurrently()

    assert Enum.all?(retry_results, &match?({:snooze, _delay}, &1))

    {retry_execution, retry_requests} =
      with_unboxed_connection(fn -> execution_and_requests(retry_execution_id) end)

    assert retry_execution.state == "retry_scheduled"
    assert retry_execution.attempt_count == 1
    assert [retry_request] = retry_requests
    assert retry_request.state == "retry_scheduled"

    {terminal_execution_id, terminal_job, terminal_bootstrap} =
      with_unboxed_connection(fn -> worker_fixture("terminal") end)

    register_cleanup(terminal_bootstrap)

    terminal_results =
      [
        fn -> ExecutionWorker.perform(%{terminal_job | attempt: 1, max_attempts: 3}) end,
        fn -> ExecutionWorker.perform(%{terminal_job | attempt: 1, max_attempts: 3}) end
      ]
      |> run_concurrently()

    assert 1 == Enum.count(terminal_results, &(&1 == {:cancel, "invalid_request"}))
    assert 1 == Enum.count(terminal_results, &match?({:snooze, _delay}, &1))

    {terminal_execution, terminal_requests} =
      with_unboxed_connection(fn -> execution_and_requests(terminal_execution_id) end)

    assert terminal_execution.state == "failed"
    assert terminal_execution.attempt_count == 1
    assert [terminal_request] = terminal_requests
    assert terminal_request.state == "failed"
    assert terminal_request.failure_code == "invalid_request"
  end

  defp waiting_gate_fixture(kind) do
    fixture = waiting_execution_fixture(kind)

    request =
      case kind do
        :approval ->
          create_approval_request!(
            fixture.context,
            fixture.invoked,
            fixture.execution,
            fixture.step_key
          )

        :context_expansion ->
          create_context_expansion_request!(
            fixture.context,
            fixture.invoked,
            fixture.execution,
            fixture.step_key
          )
      end

    Map.put(fixture, :request, request)
  end

  defp waiting_execution_fixture(kind) do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    step_key = "model:review"
    waiting_state = if kind == :approval, do: "waiting_approval", else: "waiting_context"

    waiting =
      invoked.execution
      |> Ash.Changeset.for_update(:transition, %{
        state: waiting_state,
        current_step_key: step_key
      })
      |> Ash.update!(authorize?: false)

    %{context: context, invoked: invoked, execution: waiting, step_key: step_key}
  end

  defp create_approval_request!(_context, invoked, execution, step_key) do
    ApprovalRequest
    |> Ash.Changeset.for_create(:create, approval_request_attrs(invoked, execution, step_key))
    |> Ash.create!(authorize?: false)
  end

  defp approval_request_attrs(invoked, execution, step_key) do
    %{
      execution_id: execution.id,
      authority_snapshot_id: invoked.authority_snapshot.id,
      organization_id: execution.organization_id,
      workspace_id: execution.workspace_id,
      operation_id: invoked.operation.id,
      step_key: step_key,
      execution_state_version: execution.state_version,
      requested_action: "model.generate",
      reason: "Exercise concurrent approval resolution.",
      scope_type: "workspace",
      scope_id: execution.workspace_id,
      capability_key: "agent.model.generate",
      sensitivity: "internal",
      external_write: false,
      state: "pending",
      version: 1,
      expires_at: DateTime.add(DateTime.utc_now(), 900, :second)
    }
  end

  defp create_context_expansion_request!(_context, invoked, execution, step_key) do
    ContextExpansionRequest
    |> Ash.Changeset.for_create(
      :create,
      context_expansion_request_attrs(invoked, execution, step_key)
    )
    |> Ash.create!(authorize?: false)
  end

  defp context_expansion_request_attrs(invoked, execution, step_key) do
    target = invoked.context_entries |> Enum.sort_by(& &1.ordinal) |> hd()

    %{
      execution_id: execution.id,
      current_context_package_id: invoked.context_package.id,
      authority_snapshot_id: invoked.authority_snapshot.id,
      organization_id: execution.organization_id,
      workspace_id: execution.workspace_id,
      operation_id: invoked.operation.id,
      step_key: step_key,
      execution_state_version: execution.state_version,
      target_resource_type: target.resource_type,
      target_resource_id: target.resource_id,
      target_scope_type: "workspace",
      target_scope_id: execution.workspace_id,
      access_mode: "read",
      capability_key: "agent.tool.read",
      reason: "Exercise concurrent context resolution.",
      sensitivity: "internal",
      expected_duration_seconds: 900,
      state: "pending",
      version: 1,
      expires_at: DateTime.add(DateTime.utc_now(), 900, :second)
    }
  end

  defp pending_request(fixture, :approval) do
    {
      ApprovalRequest,
      approval_request_attrs(fixture.invoked, fixture.execution, fixture.step_key)
    }
  end

  defp pending_request(fixture, :context_expansion) do
    {
      ContextExpansionRequest,
      context_expansion_request_attrs(fixture.invoked, fixture.execution, fixture.step_key)
    }
  end

  defp create_pending_request(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end

  defp decision_funs(fixture, kind) do
    decisions =
      case kind do
        :approval -> ["approved", "denied"]
        :context_expansion -> ["denied", "cancelled"]
      end

    Enum.map(decisions, &decision_fun(fixture, kind, &1))
  end

  defp decision_fun(fixture, kind, decision) do
    fn ->
      reason = "Concurrent #{kind} #{decision}."
      attrs = decision_attrs(fixture.request, kind, decision, reason)
      action = decision_operation_action(kind)

      {:ok, operation} =
        Operations.start_command(
          fixture.context.session,
          action,
          "#{kind}-race-#{fixture.context.suffix}-#{decision}",
          attrs
        )

      resolve_gate(fixture, kind, operation, decision, reason)
    end
  end

  defp decision_attrs(request, :approval, decision, reason) do
    %{
      approval_request_id: request.id,
      expected_version: request.version,
      decision: decision,
      resolution_reason: reason
    }
  end

  defp decision_attrs(request, :context_expansion, decision, reason) do
    %{
      context_expansion_request_id: request.id,
      expected_version: request.version,
      decision: decision,
      resolution_reason: reason
    }
  end

  defp decision_operation_action(:approval), do: :agent_approval_resolve
  defp decision_operation_action(:context_expansion), do: :agent_context_expansion_resolve

  defp resolve_gate(fixture, :approval, operation, "approved", reason) do
    AgentRuntime.approve(
      fixture.context.session,
      operation,
      fixture.request.id,
      fixture.request.version,
      reason
    )
  end

  defp resolve_gate(fixture, :approval, operation, "denied", reason) do
    AgentRuntime.deny_approval(
      fixture.context.session,
      operation,
      fixture.request.id,
      fixture.request.version,
      reason
    )
  end

  defp resolve_gate(fixture, :context_expansion, operation, "approved", reason) do
    AgentRuntime.approve_context_expansion(
      fixture.context.session,
      operation,
      fixture.request.id,
      fixture.request.version,
      reason
    )
  end

  defp resolve_gate(fixture, :context_expansion, operation, "denied", reason) do
    AgentRuntime.deny_context_expansion(
      fixture.context.session,
      operation,
      fixture.request.id,
      fixture.request.version,
      reason
    )
  end

  defp resolve_gate(fixture, :context_expansion, operation, "cancelled", reason) do
    AgentRuntime.cancel_context_expansion(
      fixture.context.session,
      operation,
      fixture.request.id,
      fixture.request.version,
      reason
    )
  end

  defp assert_one_gate_winner(results, request, stale_error) do
    assert 1 == Enum.count(results, &match?({:ok, _result}, &1))

    assert 1 ==
             Enum.count(results, fn
               {:error, {^stale_error, request_id, actual_version}}
               when request_id == request.id and actual_version == request.version + 1 ->
                 true

               _other ->
                 false
             end)
  end

  defp worker_fixture(fixture_id) do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = AgentRuntimeSupport.execution_jobs(invoked.execution.id)

    {
      invoked.execution.id,
      %{job | args: Map.put(job.args, "fixture_id", fixture_id)},
      context.bootstrap
    }
  end

  defp execution_and_requests(execution_id) do
    execution = Ash.get!(AgentExecution, execution_id, authorize?: false)

    requests =
      ModelRequest
      |> Ash.Query.filter(execution_id == ^execution_id)
      |> Ash.read!(authorize?: false)

    {execution, requests}
  end

  defp register_cleanup(bootstrap) do
    organization_id = bootstrap.organization.id
    organization_slug = bootstrap.organization.slug
    owner_email = bootstrap.principal.email
    agent_email = "run-review+#{organization_id}@agents.office-graph.local"

    on_exit(fn ->
      with_unboxed_connection(fn ->
        AgentRuntimeCleanup.cleanup_scope!(organization_id)
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
        cleanup_owner_principal!(agent_email)
      end)
    end)
  end
end
