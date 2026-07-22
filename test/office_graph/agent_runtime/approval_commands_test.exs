defmodule OfficeGraph.AgentRuntime.ApprovalCommandsTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Audit, Operations, Revisions}

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ApprovalRequest,
    ExecutionWorker,
    GateExpiryWorker,
    ModelRequest
  }

  alias OfficeGraph.TestSupport.AgentRuntimeSupport
  alias OfficeGraph.Integrations.IntegrationCredential

  import OfficeGraph.TestSupport.AgentRuntimeSupport,
    only: [approval_resume_jobs: 1, execution_jobs: 1, gate_expiry_jobs: 2]

  require Ash.Query

  setup do
    original = Application.get_env(:office_graph, :deterministic_model_approval_required)
    Application.put_env(:office_graph, :deterministic_model_approval_required, true)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:office_graph, :deterministic_model_approval_required)
      else
        Application.put_env(:office_graph, :deterministic_model_approval_required, original)
      end
    end)

    :ok
  end

  test "an approval-gated step creates one bounded request before waiting" do
    context = AgentRuntimeSupport.invocation_fixture()

    credential =
      Ash.create!(
        IntegrationCredential,
        %{
          id: Ecto.UUID.generate(),
          organization_id: context.bootstrap.organization.id,
          workspace_id: context.bootstrap.workspace.id,
          kind: "secret_reference",
          secret_reference: "test-secret://agent-runtime/approval/#{context.suffix}",
          status: "active",
          operation_id: context.binding.operation_id
        },
        action: :create,
        authorize?: false
      )

    OfficeGraph.Repo.query!(
      "UPDATE agent_definitions SET model_credential_id = $1 WHERE id = $2",
      [Ecto.UUID.dump!(credential.id), Ecto.UUID.dump!(context.definition.id)]
    )

    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    assert :ok = ExecutionWorker.perform(%{job | attempt: 2, max_attempts: 3})

    waiting = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    assert [request] =
             ApprovalRequest
             |> Ash.Query.filter(execution_id == ^waiting.id)
             |> Ash.read!(authorize?: false)

    assert waiting.state == "waiting_approval"
    assert request.state == "pending"
    assert request.execution_id == waiting.id
    assert request.execution_state_version == waiting.state_version
    assert request.authority_snapshot_id == invoked.authority_snapshot.id
    assert request.operation_id == job.args["operation_id"]
    assert request.step_key == "model:review"
    assert request.requested_action == "model.generate"
    assert request.scope_type == "workspace"
    assert request.scope_id == context.bootstrap.workspace.id
    assert request.capability_key == "agent.model.generate"
    assert request.credential_id == credential.id
    assert request.sensitivity == "internal"
    refute request.external_write
    assert DateTime.compare(request.expires_at, DateTime.utc_now()) == :gt
  end

  test "approval resumes exactly its matching step once with full provenance" do
    first = waiting_approval_fixture()
    other = waiting_approval_fixture()

    attrs = %{
      approval_request_id: first.request.id,
      expected_version: first.request.version,
      resolution_reason: "Approve the bounded read-only model step."
    }

    operation_result =
      try do
        Operations.start_command(
          first.context.session,
          :agent_approval_resolve,
          "approve-agent-step-#{first.context.suffix}",
          Map.put(attrs, :decision, "approved")
        )
      rescue
        KeyError -> :missing_operation_action
      end

    assert {:ok, operation} = operation_result

    result =
      approve(
        first.context.session,
        operation,
        first.request.id,
        first.request.version,
        attrs.resolution_reason
      )

    assert {:ok, resolved} = result
    assert resolved.request.state == "approved"
    assert resolved.request.version == first.request.version + 1
    assert resolved.request.resolution_operation_id == operation.id
    assert resolved.execution.state == "queued"
    assert resolved.execution.current_step_key == first.request.step_key
    assert Audit.count_for_operation(operation.id) == 1
    assert Revisions.count_for_operation(operation.id) == 1

    assert [resume_job] = approval_resume_jobs(first.request.id)
    assert approval_resume_jobs(other.request.id) == []

    assert {:ok, replayed} =
             approve(
               first.context.session,
               operation,
               first.request.id,
               first.request.version,
               attrs.resolution_reason
             )

    assert replayed.request.id == resolved.request.id
    assert replayed.request.version == resolved.request.version
    assert [_same_resume_job] = approval_resume_jobs(first.request.id)
    assert Audit.count_for_operation(operation.id) == 1
    assert Revisions.count_for_operation(operation.id) == 1

    assert :ok = ExecutionWorker.perform(%{resume_job | attempt: 1, max_attempts: 3})
    assert Ash.get!(AgentExecution, first.execution.id, authorize?: false).state == "completed"

    assert Ash.get!(AgentExecution, other.execution.id, authorize?: false).state ==
             "waiting_approval"
  end

  test "an approved step keeps its gate authority across bounded adapter retries" do
    fixture = waiting_approval_fixture()
    reason = "Approve the bounded retrying model step."

    attrs = %{
      approval_request_id: fixture.request.id,
      expected_version: fixture.request.version,
      decision: "approved",
      resolution_reason: reason
    }

    {:ok, operation} =
      Operations.start_command(
        fixture.context.session,
        :agent_approval_resolve,
        "approve-retrying-agent-step-#{fixture.context.suffix}",
        attrs
      )

    assert {:ok, _resolved} =
             AgentRuntime.approve(
               fixture.context.session,
               operation,
               fixture.request.id,
               fixture.request.version,
               reason
             )

    [resume_job] = approval_resume_jobs(fixture.request.id)
    retry_job = %{resume_job | args: Map.put(resume_job.args, "fixture_id", "retryable")}

    assert {:snooze, 1} = ExecutionWorker.perform(%{retry_job | attempt: 1, max_attempts: 3})

    assert Ash.get!(AgentExecution, fixture.execution.id, authorize?: false).state ==
             "retry_scheduled"

    assert {:snooze, 1} = ExecutionWorker.perform(%{retry_job | attempt: 2, max_attempts: 3})

    retried = Ash.get!(AgentExecution, fixture.execution.id, authorize?: false)
    assert retried.state == "retry_scheduled"
    assert retried.attempt_count == 2
    assert Ash.read_one!(ModelRequest, authorize?: false).state == "retry_scheduled"
  end

  test "an unanswered approval expires durably instead of leaving its execution waiting" do
    fixture = waiting_approval_fixture()
    assert [expiry_job] = gate_expiry_jobs("approval", fixture.request.id)

    OfficeGraph.Repo.query!(
      "UPDATE agent_approval_requests SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(fixture.request.id)]
    )

    assert :ok = GateExpiryWorker.perform(%{expiry_job | attempt: 1, max_attempts: 3})

    expired = Ash.get!(ApprovalRequest, fixture.request.id, authorize?: false)
    execution = Ash.get!(AgentExecution, fixture.execution.id, authorize?: false)

    assert expired.state == "expired"
    assert expired.version == fixture.request.version + 1
    assert expired.resolution_reason == "approval_expired"
    assert execution.state == "failed"
    assert execution.failure_code == "agent_approval_expired"
  end

  test "denied and cancelled approvals terminalize without a resume" do
    Enum.each(["denied", "cancelled"], fn decision ->
      fixture = waiting_approval_fixture()
      reason = "Resolve the bounded step as #{decision}."

      attrs = %{
        approval_request_id: fixture.request.id,
        expected_version: fixture.request.version,
        decision: decision,
        resolution_reason: reason
      }

      {:ok, operation} =
        Operations.start_command(
          fixture.context.session,
          :agent_approval_resolve,
          "#{decision}-agent-step-#{fixture.context.suffix}",
          attrs
        )

      resolver = if decision == "denied", do: :deny_approval, else: :cancel_approval

      assert {:ok, resolved} =
               apply(AgentRuntime, resolver, [
                 fixture.context.session,
                 operation,
                 fixture.request.id,
                 fixture.request.version,
                 reason
               ])

      assert resolved.request.state == decision
      assert resolved.execution.state == "cancelled"
      assert resolved.execution.failure_code == "approval_#{decision}"
      assert approval_resume_jobs(fixture.request.id) == []
      assert Audit.count_for_operation(operation.id) == 1
      assert Revisions.count_for_operation(operation.id) == 1
    end)
  end

  test "stale and expired approvals return stable conflicts without a resume" do
    stale = waiting_approval_fixture()

    stale_attrs = %{
      approval_request_id: stale.request.id,
      expected_version: stale.request.version + 1,
      decision: "approved",
      resolution_reason: "Stale approval."
    }

    {:ok, stale_operation} =
      Operations.start_command(
        stale.context.session,
        :agent_approval_resolve,
        "stale-agent-step-#{stale.context.suffix}",
        stale_attrs
      )

    assert {:error, {:stale_agent_approval, _, 1}} =
             AgentRuntime.approve(
               stale.context.session,
               stale_operation,
               stale.request.id,
               stale.request.version + 1,
               stale_attrs.resolution_reason
             )

    assert approval_resume_jobs(stale.request.id) == []

    expired = waiting_approval_fixture()

    OfficeGraph.Repo.query!(
      "UPDATE agent_approval_requests SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(expired.request.id)]
    )

    expired_attrs = %{
      approval_request_id: expired.request.id,
      expected_version: expired.request.version,
      decision: "approved",
      resolution_reason: "Expired approval."
    }

    {:ok, expired_operation} =
      Operations.start_command(
        expired.context.session,
        :agent_approval_resolve,
        "expired-agent-step-#{expired.context.suffix}",
        expired_attrs
      )

    assert {:error, {:agent_approval_expired, _}} =
             AgentRuntime.approve(
               expired.context.session,
               expired_operation,
               expired.request.id,
               expired.request.version,
               expired_attrs.resolution_reason
             )

    assert approval_resume_jobs(expired.request.id) == []
  end

  defp waiting_approval_fixture do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})

    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    request =
      ApprovalRequest
      |> Ash.Query.filter(execution_id == ^execution.id and state == "pending")
      |> Ash.read_one!(authorize?: false)

    %{context: context, execution: execution, invoked: invoked, job: job, request: request}
  end

  defp approve(session, operation, request_id, expected_version, reason) do
    AgentRuntime.approve(session, operation, request_id, expected_version, reason)
  end
end
