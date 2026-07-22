defmodule OfficeGraph.AgentRuntime.ContextExpansionCommandsTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Audit, Operations, Repo, Revisions}

  alias OfficeGraph.AgentRuntime.{
    AgentExecution,
    ContextEntry,
    ContextExpansionRequest,
    ContextPackage,
    ExecutionWorker,
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

  defp waiting_context_fixture do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    target = Enum.min_by(invoked.context_entries, & &1.ordinal)

    Repo.query!(
      "UPDATE agent_context_entries SET posture = 'expansion_required' WHERE id = $1",
      [Ecto.UUID.dump!(target.id)]
    )

    assert :ok = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
    execution = Ash.get!(AgentExecution, invoked.execution.id, authorize?: false)

    request =
      ContextExpansionRequest
      |> Ash.Query.filter(execution_id == ^execution.id and state == "pending")
      |> Ash.read_one!(authorize?: false)

    target = Ash.get!(ContextEntry, target.id, authorize?: false)

    %{
      context: context,
      execution: execution,
      request: request,
      context_package: invoked.context_package,
      target: target
    }
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
