defmodule OfficeGraph.AgentRuntime.ContextExpansionCommandsTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Audit, Operations, Repo, Revisions}

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ApprovalRequest,
    ContextEntry,
    ContextExpansionRequest,
    ContextPackage,
    ExecutionWorker,
    GateExpiryWorker,
    ModelRequest
  }

  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  require Ash.Query

  test "an exact bounded context expansion creates an immutable package and resumes once" do
    fixture = waiting_context_fixture()
    request = fixture.request

    attrs = %{
      context_expansion_request_id: request.id,
      expected_version: request.version,
      decision: "approved",
      resolution_reason: "Permit the exact workspace-scoped reference for this step."
    }

    {:ok, operation} =
      Operations.start_command(
        fixture.context.session,
        :agent_context_expansion_resolve,
        "approve-context-expansion-#{fixture.context.suffix}",
        attrs
      )

    assert {:ok, resolved} =
             AgentRuntime.approve_context_expansion(
               fixture.context.session,
               operation,
               request.id,
               request.version,
               attrs.resolution_reason
             )

    assert resolved.request.state == "approved"
    assert resolved.request.version == 2
    assert resolved.execution.state == "queued"
    assert resolved.context_package.version == 2
    assert resolved.context_package.previous_package_id == fixture.context_package.id
    assert resolved.context_package.expansion_request_id == request.id
    refute resolved.context_package.package_hash == fixture.context_package.package_hash

    old_target = Ash.get!(ContextEntry, fixture.target.id, authorize?: false)
    assert old_target.posture == "expansion_required"

    assert [expanded_target] =
             ContextEntry
             |> Ash.Query.filter(
               context_package_id == ^resolved.context_package.id and
                 resource_type == ^request.target_resource_type and
                 resource_id == ^request.target_resource_id
             )
             |> Ash.read!(authorize?: false)

    assert expanded_target.posture == "included"
    assert expanded_target.rationale_code == "approved_context_expansion"
    assert Audit.count_for_operation(operation.id) == 1
    assert Revisions.count_for_operation(operation.id) == 1

    assert [resume_job] = expansion_resume_jobs(request.id)
    assert :ok = ExecutionWorker.perform(%{resume_job | attempt: 1, max_attempts: 3})

    completed = Ash.get!(AgentExecution, fixture.execution.id, authorize?: false)
    model_request = Ash.read_one!(ModelRequest, authorize?: false)
    assert completed.state == "completed"
    assert model_request.context_package_id == resolved.context_package.id

    assert {:ok, replayed} =
             AgentRuntime.approve_context_expansion(
               fixture.context.session,
               operation,
               request.id,
               request.version,
               attrs.resolution_reason
             )

    assert replayed.context_package.id == resolved.context_package.id
    assert Repo.aggregate(ContextPackage, :count) == 2
    assert [_same_job] = expansion_resume_jobs(request.id)
    assert Audit.count_for_operation(operation.id) == 1
    assert Revisions.count_for_operation(operation.id) == 1
  end

  test "sequential bounded expansions count only the target changed by each decision" do
    fixture = waiting_context_fixture(expansion_count: 2)
    first_request = fixture.request

    first = approve_expansion(fixture, first_request, "Approve the first bounded reference.")
    assert first.context_package.version == 2

    [first_resume] = expansion_resume_jobs(first_request.id)
    assert :ok = ExecutionWorker.perform(%{first_resume | attempt: 1, max_attempts: 3})

    waiting_again = Ash.get!(AgentExecution, fixture.execution.id, authorize?: false)
    assert waiting_again.state == "waiting_context"

    second_request =
      ContextExpansionRequest
      |> Ash.Query.filter(
        execution_id == ^fixture.execution.id and state == "pending" and
          id != ^first_request.id
      )
      |> Ash.read_one!(authorize?: false)

    second = approve_expansion(fixture, second_request, "Approve the second bounded reference.")
    assert second.context_package.version == 3
    assert second.context_package.previous_package_id == first.context_package.id
    assert second.context_package.expansion_request_id == second_request.id

    assert 2 ==
             ContextEntry
             |> Ash.Query.filter(
               context_package_id == ^second.context_package.id and posture == "included" and
                 rationale_code == "approved_context_expansion"
             )
             |> Ash.read!(authorize?: false)
             |> length()
  end

  test "sequential expansions revalidate every grant in the successor package lineage" do
    fixture = waiting_context_fixture(expansion_count: 2)
    first_request = fixture.request

    first = approve_expansion(fixture, first_request, "Approve the first bounded reference.")
    [first_resume] = expansion_resume_jobs(first_request.id)
    assert :ok = ExecutionWorker.perform(%{first_resume | attempt: 1, max_attempts: 3})

    second_request =
      ContextExpansionRequest
      |> Ash.Query.filter(
        execution_id == ^fixture.execution.id and state == "pending" and
          id != ^first_request.id
      )
      |> Ash.read_one!(authorize?: false)

    second = approve_expansion(fixture, second_request, "Approve the second bounded reference.")
    [second_resume] = expansion_resume_jobs(second_request.id)

    Repo.query!(
      "UPDATE agent_context_expansion_requests SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(first_request.id)]
    )

    assert {:cancel, "agent_authority_revoked"} =
             ExecutionWorker.perform(%{second_resume | attempt: 1, max_attempts: 3})

    assert second.context_package.previous_package_id == first.context_package.id
    assert Repo.aggregate(ModelRequest, :count) == 0

    failed = Ash.get!(AgentExecution, fixture.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "agent_authority_revoked"
  end

  test "an approved expansion remains valid while its exact step retries" do
    fixture = waiting_context_fixture()

    resolved =
      approve_expansion(fixture, fixture.request, "Approve the bounded retrying reference.")

    assert resolved.context_package.version == 2
    [resume_job] = expansion_resume_jobs(fixture.request.id)
    retry_job = %{resume_job | args: Map.put(resume_job.args, "fixture_id", "retryable")}

    assert {:snooze, 1} = ExecutionWorker.perform(%{retry_job | attempt: 1, max_attempts: 3})
    assert {:snooze, 1} = ExecutionWorker.perform(%{retry_job | attempt: 2, max_attempts: 3})

    retried = Ash.get!(AgentExecution, fixture.execution.id, authorize?: false)
    assert retried.state == "retry_scheduled"
    assert retried.attempt_count == 2
  end

  test "an approval resume preserves and revalidates its prior expansion authority" do
    original = Application.get_env(:office_graph, :deterministic_model_approval_required)
    Application.put_env(:office_graph, :deterministic_model_approval_required, true)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:office_graph, :deterministic_model_approval_required)
      else
        Application.put_env(:office_graph, :deterministic_model_approval_required, original)
      end
    end)

    fixture = waiting_context_fixture()
    expansion = approve_expansion(fixture, fixture.request, "Approve bounded context first.")
    [expansion_resume] = expansion_resume_jobs(fixture.request.id)

    assert :ok = ExecutionWorker.perform(%{expansion_resume | attempt: 1, max_attempts: 3})

    approval =
      ApprovalRequest
      |> Ash.Query.filter(execution_id == ^fixture.execution.id and state == "pending")
      |> Ash.read_one!(authorize?: false)

    Repo.query!(
      "UPDATE agent_context_expansion_requests SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(fixture.request.id)]
    )

    approval_attrs = %{
      approval_request_id: approval.id,
      expected_version: approval.version,
      decision: "approved",
      resolution_reason: "Approve the model step while retaining its context grant."
    }

    {:ok, approval_operation} =
      Operations.start_command(
        fixture.context.session,
        :agent_approval_resolve,
        "approve-after-expansion-#{fixture.context.suffix}",
        approval_attrs
      )

    assert {:ok, _resolved} =
             AgentRuntime.approve(
               fixture.context.session,
               approval_operation,
               approval.id,
               approval.version,
               approval_attrs.resolution_reason
             )

    [approval_resume] = approval_resume_jobs(approval.id)

    assert {:cancel, "agent_authority_revoked"} =
             ExecutionWorker.perform(%{approval_resume | attempt: 1, max_attempts: 3})

    assert approval.context_expansion_request_id == fixture.request.id
    assert approval_resume.args["context_expansion_request_id"] == fixture.request.id
    assert expansion.context_package.expansion_request_id == fixture.request.id
    assert Repo.aggregate(ModelRequest, :count) == 0

    failed = Ash.get!(AgentExecution, fixture.execution.id, authorize?: false)
    assert failed.state == "failed"
    assert failed.failure_code == "agent_authority_revoked"
  end

  test "context expansion preserves each entry source version in the successor package" do
    fixture = waiting_context_fixture()
    assert %DateTime{} = fixture.target.source_version

    resolved =
      approve_expansion(fixture, fixture.request, "Approve the versioned bounded reference.")

    expanded =
      ContextEntry
      |> Ash.Query.filter(
        context_package_id == ^resolved.context_package.id and
          resource_type == ^fixture.request.target_resource_type and
          resource_id == ^fixture.request.target_resource_id
      )
      |> Ash.read_one!(authorize?: false)

    assert expanded.source_version == fixture.target.source_version
  end

  test "an unanswered context expansion expires and terminalizes its waiting execution" do
    fixture = waiting_context_fixture()
    assert [expiry_job] = gate_expiry_jobs(fixture.request.id)

    Repo.query!(
      "UPDATE agent_context_expansion_requests SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(fixture.request.id)]
    )

    assert :ok = GateExpiryWorker.perform(%{expiry_job | attempt: 1, max_attempts: 3})

    expired = Ash.get!(ContextExpansionRequest, fixture.request.id, authorize?: false)
    execution = Ash.get!(AgentExecution, fixture.execution.id, authorize?: false)

    assert expired.state == "expired"
    assert expired.version == fixture.request.version + 1
    assert expired.resolution_reason == "context_expansion_expired"
    assert execution.state == "failed"
    assert execution.failure_code == "agent_context_expansion_expired"
  end

  test "stale and expired context expansion decisions do not resume" do
    stale = waiting_context_fixture()

    stale_attrs = %{
      context_expansion_request_id: stale.request.id,
      expected_version: stale.request.version + 1,
      decision: "approved",
      resolution_reason: "Stale decision."
    }

    {:ok, stale_operation} =
      Operations.start_command(
        stale.context.session,
        :agent_context_expansion_resolve,
        "stale-context-expansion-#{stale.context.suffix}",
        stale_attrs
      )

    assert {:error, {:stale_agent_context_expansion, _, 1}} =
             AgentRuntime.approve_context_expansion(
               stale.context.session,
               stale_operation,
               stale.request.id,
               stale.request.version + 1,
               stale_attrs.resolution_reason
             )

    assert expansion_resume_jobs(stale.request.id) == []

    expired = waiting_context_fixture()

    Repo.query!(
      "UPDATE agent_context_expansion_requests SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [Ecto.UUID.dump!(expired.request.id)]
    )

    expired_attrs = %{
      context_expansion_request_id: expired.request.id,
      expected_version: expired.request.version,
      decision: "approved",
      resolution_reason: "Expired decision."
    }

    {:ok, expired_operation} =
      Operations.start_command(
        expired.context.session,
        :agent_context_expansion_resolve,
        "expired-context-expansion-#{expired.context.suffix}",
        expired_attrs
      )

    assert {:error, {:agent_context_expansion_expired, _}} =
             AgentRuntime.approve_context_expansion(
               expired.context.session,
               expired_operation,
               expired.request.id,
               expired.request.version,
               expired_attrs.resolution_reason
             )

    assert expansion_resume_jobs(expired.request.id) == []
  end

  defp waiting_context_fixture(opts \\ []) do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    expansion_count = Keyword.get(opts, :expansion_count, 1)

    targets =
      invoked.context_entries
      |> Enum.sort_by(& &1.ordinal)
      |> Enum.take(expansion_count)

    Repo.query!(
      "UPDATE agent_context_entries SET posture = 'expansion_required' WHERE id = ANY($1::uuid[])",
      [Enum.map(targets, &Ecto.UUID.dump!(&1.id))]
    )

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    request =
      ContextExpansionRequest
      |> Ash.Query.filter(execution_id == ^execution.id and state == "pending")
      |> Ash.read_one!(authorize?: false)

    target = targets |> hd() |> then(&Ash.get!(ContextEntry, &1.id, authorize?: false))

    %{
      context: context,
      execution: execution,
      request: request,
      context_package: invoked.context_package,
      target: target
    }
  end

  defp approve_expansion(fixture, request, reason) do
    attrs = %{
      context_expansion_request_id: request.id,
      expected_version: request.version,
      decision: "approved",
      resolution_reason: reason
    }

    {:ok, operation} =
      Operations.start_command(
        fixture.context.session,
        :agent_context_expansion_resolve,
        "approve-context-expansion-#{request.id}",
        attrs
      )

    assert {:ok, resolved} =
             AgentRuntime.approve_context_expansion(
               fixture.context.session,
               operation,
               request.id,
               request.version,
               reason
             )

    resolved
  end

  defp expansion_resume_jobs(request_id) do
    Oban.Job
    |> where(
      [job],
      job.worker == ^inspect(ExecutionWorker) and
        fragment("?->>'context_expansion_request_id'", job.args) == ^request_id
    )
    |> Repo.all()
  end

  defp approval_resume_jobs(request_id) do
    Oban.Job
    |> where(
      [job],
      job.worker == ^inspect(ExecutionWorker) and
        fragment("?->>'approval_request_id'", job.args) == ^request_id
    )
    |> Repo.all()
  end

  defp gate_expiry_jobs(request_id) do
    Oban.Job
    |> where(
      [job],
      job.worker == ^inspect(GateExpiryWorker) and
        fragment("?->>'request_kind'", job.args) == "context_expansion" and
        fragment("?->>'request_id'", job.args) == ^request_id
    )
    |> Repo.all()
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
