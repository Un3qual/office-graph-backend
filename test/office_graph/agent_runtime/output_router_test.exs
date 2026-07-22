defmodule OfficeGraph.AgentRuntime.OutputRouterTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Audit, Operations, Repo, Revisions}
  alias OfficeGraph.AgentRuntime.{ExecutionWorker, ModelOutput, OutputRouter}
  alias OfficeGraph.NodeConversations.ConversationMessage
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Runs.{ExecutionObservation, Run}
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  alias OfficeGraph.WorkGraph.{
    EvidenceCandidate,
    EvidenceItem,
    ReviewFinding,
    Task,
    VerificationResult
  }

  for {classification, resource} <- [
        proposal: ProposedGraphChange,
        finding: ProposedGraphChange,
        evidence_candidate: EvidenceCandidate,
        message: ConversationMessage,
        observation: ExecutionObservation
      ] do
    @classification classification
    @resource resource

    test "routes #{classification} through its owning domain exactly once" do
      fixture = output_fixture()
      output = output(@classification)
      before_counts = mutation_counts()
      before_run = Ash.get!(Run, fixture.execution.run_id, authorize?: false)

      assert {:ok, first} =
               Repo.transaction(fn ->
                 OutputRouter.route!(
                   fixture.operation,
                   fixture.execution,
                   fixture.context_package,
                   "model:review",
                   output
                 )
               end)

      assert first.execution_id == fixture.execution.id
      assert first.context_package_id == fixture.context_package.id
      assert first.step_key == "model:review"

      assert {:ok, replay} =
               Repo.transaction(fn ->
                 OutputRouter.route!(
                   fixture.operation,
                   fixture.execution,
                   fixture.context_package,
                   "model:review",
                   output
                 )
               end)

      assert replay.id == first.id
      assert Repo.aggregate(@resource, :count) == 1
      assert Audit.count_for_operation(fixture.operation.id) == 1
      assert Revisions.count_for_operation(fixture.operation.id) == 1

      assert_no_direct_effects(
        @classification,
        before_counts,
        fixture.execution.run_id,
        before_run
      )
    end
  end

  defp output_fixture do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    [job] = execution_jobs(invoked.execution.id)
    {:ok, operation} = Operations.read_operation(job.args["operation_id"])

    %{
      execution: invoked.execution,
      context_package: invoked.context_package,
      operation: operation
    }
  end

  defp output(classification) do
    content =
      case classification do
        :proposal -> %{"intent" => "follow_up"}
        :finding -> %{"summary" => "Review a bounded issue"}
        :evidence_candidate -> %{"check" => "Static check material"}
        :message -> %{"body" => "A bounded run message"}
        :observation -> %{"subject" => "A non-authoritative observation"}
      end

    %ModelOutput{
      classification: classification,
      safe_summary: "Agent #{classification} output",
      structured_content: %{Atom.to_string(classification) => content}
    }
  end

  defp mutation_counts do
    %{
      tasks: Repo.aggregate(Task, :count),
      findings: Repo.aggregate(ReviewFinding, :count),
      evidence_items: Repo.aggregate(EvidenceItem, :count),
      verification_results: Repo.aggregate(VerificationResult, :count)
    }
  end

  defp assert_no_direct_effects(classification, before, run_id, before_run) do
    assert mutation_counts() == before
    after_run = Ash.get!(Run, run_id, authorize?: false)
    assert after_run.state == before_run.state
    assert after_run.aggregate_state == before_run.aggregate_state
    assert after_run.verification_state == before_run.verification_state

    case classification do
      kind when kind in [:proposal, :finding] ->
        assert [proposal] = Ash.read!(ProposedGraphChange, authorize?: false)
        assert proposal.status == "pending"

      :evidence_candidate ->
        assert [candidate] = Ash.read!(EvidenceCandidate, authorize?: false)
        assert candidate.candidate_state == "candidate"
        assert candidate.trust_basis == "agent_reported"

      _other ->
        :ok
    end
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
