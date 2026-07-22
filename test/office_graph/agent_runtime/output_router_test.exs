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
      fixture = output_fixture(requested_capabilities: capabilities_for(@classification))
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

  test "rejects output classifications outside the definition allowlist" do
    fixture = output_fixture()
    before_counts = mutation_counts()

    Repo.query!(
      "UPDATE agent_definitions SET allowed_output_kinds = ARRAY['message']::text[] WHERE id = $1",
      [Ecto.UUID.dump!(fixture.execution.definition_id)]
    )

    assert {:error, {:agent_output_kind_not_allowed, "proposal"}} =
             Repo.transaction(fn ->
               OutputRouter.route!(
                 fixture.operation,
                 fixture.execution,
                 fixture.context_package,
                 "model:review",
                 output(:proposal)
               )
             end)

    assert mutation_counts() == before_counts
    assert Repo.aggregate(ProposedGraphChange, :count) == 0
    assert Audit.count_for_operation(fixture.operation.id) == 0
    assert Revisions.count_for_operation(fixture.operation.id) == 0
  end

  test "routes evidence to the required check for the execution graph item" do
    fixture =
      output_fixture(
        verification_check_count: 2,
        selected_verification_check_index: 1,
        requested_capabilities: capabilities_for(:evidence_candidate)
      )

    assert {:ok, candidate} =
             Repo.transaction(fn ->
               OutputRouter.route!(
                 fixture.operation,
                 fixture.execution,
                 fixture.context_package,
                 "model:review",
                 output(:evidence_candidate)
               )
             end)

    assert candidate.verification_check_id == fixture.verification_check.id
    refute candidate.verification_check_id == hd(fixture.verification_checks).id
  end

  for {classification, required_capability, resource} <- [
        {:proposal, "proposal.create", ProposedGraphChange},
        {:finding, "proposal.create", ProposedGraphChange},
        {:evidence_candidate, "evidence.suggest", EvidenceCandidate}
      ] do
    @classification classification
    @classification_string Atom.to_string(classification)
    @required_capability required_capability
    @resource resource

    test "rejects #{classification} without #{@required_capability} in the authority snapshot" do
      fixture = output_fixture(requested_capabilities: ["agent.model.generate"])
      before_counts = mutation_counts()

      assert {:error,
              {:agent_output_capability_not_authorized, @classification_string,
               @required_capability}} =
               Repo.transaction(fn ->
                 OutputRouter.route!(
                   fixture.operation,
                   fixture.execution,
                   fixture.context_package,
                   "model:review",
                   output(@classification)
                 )
               end)

      assert mutation_counts() == before_counts
      assert Repo.aggregate(@resource, :count) == 0
      assert Audit.count_for_operation(fixture.operation.id) == 0
      assert Revisions.count_for_operation(fixture.operation.id) == 0
    end
  end

  defp output_fixture(opts \\ []) do
    requested_capabilities = Keyword.get(opts, :requested_capabilities)

    context =
      AgentRuntimeSupport.invocation_fixture(Keyword.delete(opts, :requested_capabilities))

    invoked =
      if requested_capabilities,
        do:
          AgentRuntimeSupport.invoke_human(context, %{
            requested_capabilities: requested_capabilities
          }),
        else: AgentRuntimeSupport.invoke_human(context)

    [job] = execution_jobs(invoked.execution.id)
    {:ok, operation} = Operations.read_operation(job.args["operation_id"])

    %{
      execution: invoked.execution,
      context_package: invoked.context_package,
      operation: operation,
      verification_check: context.verification_check,
      verification_checks: context.verification_checks
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

  defp capabilities_for(classification) when classification in [:proposal, :finding],
    do: ["agent.model.generate", "proposal.create"]

  defp capabilities_for(:evidence_candidate),
    do: ["agent.model.generate", "evidence.suggest"]

  defp capabilities_for(classification) when classification in [:message, :observation],
    do: ["agent.model.generate"]

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
