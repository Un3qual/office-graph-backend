defmodule OfficeGraph.WorkPackets.WorkRunEvidenceTest do
  use OfficeGraph.TestSupport.WorkPacketCommandLoopSupport

  test "observation recording validates run check and graph references" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Observation Scope A",
        workspace_slug: "observation-scope-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Observation Scope B",
        workspace_slug: "observation-scope-b"
      )

    {:ok, required_check} = create_required_verification_check(first_scope.session)
    {:ok, unrelated_check} = create_required_verification_check(first_scope.session)
    {:ok, foreign_check} = create_required_verification_check(second_scope.session)
    {:ok, run} = create_ready_run(first_scope.session, required_check)

    {:ok, foreign_operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "foreign-observation-reference"
      )

    assert {:error, error} =
             Runs.record_observation(first_scope.session, foreign_operation, run.run, %{
               source_kind: "human",
               source_identity: "manual:foreign-observation-reference",
               idempotency_key: "foreign-observation-reference",
               observed_status: "passed",
               normalized_status: "succeeded",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               verification_check_id: foreign_check.id,
               graph_item_id: foreign_check.graph_item_id,
               rationale: "Foreign references are rejected."
             })

    assert Exception.message(error) =~
             "verification_check_id must reference an existing record in the target scope"

    {:ok, unrelated_operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "unrequired-observation-reference"
      )

    assert {:error, error} =
             Runs.record_observation(first_scope.session, unrelated_operation, run.run, %{
               source_kind: "human",
               source_identity: "manual:unrequired-observation-reference",
               idempotency_key: "unrequired-observation-reference",
               observed_status: "passed",
               normalized_status: "succeeded",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               verification_check_id: unrelated_check.id,
               graph_item_id: unrelated_check.graph_item_id,
               rationale: "Unrequired checks are rejected."
             })

    assert Exception.message(error) =~
             "verification_check_id must reference a required check for the run"

    {:ok, mismatched_operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "mismatched-observation-reference"
      )

    assert {:error, error} =
             Runs.record_observation(first_scope.session, mismatched_operation, run.run, %{
               source_kind: "human",
               source_identity: "manual:mismatched-observation-reference",
               idempotency_key: "mismatched-observation-reference",
               observed_status: "passed",
               normalized_status: "succeeded",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               verification_check_id: required_check.id,
               graph_item_id: unrelated_check.graph_item_id,
               rationale: "Mismatched graph item is rejected."
             })

    assert Exception.message(error) =~
             "graph_item_id must match the verification check graph item"

    {:ok, graph_only_operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "unrelated-graph-only-observation-reference"
      )

    assert {:error, error} =
             Runs.record_observation(first_scope.session, graph_only_operation, run.run, %{
               source_kind: "human",
               source_identity: "manual:unrelated-graph-only-observation-reference",
               idempotency_key: "unrelated-graph-only-observation-reference",
               observed_status: "passed",
               normalized_status: "succeeded",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               graph_item_id: unrelated_check.graph_item_id,
               rationale: "Unrelated graph-item-only observations are rejected."
             })

    assert Exception.message(error) =~
             "graph_item_id must reference a graph item selected by the run"

    {:ok, summary} = Runs.get_summary(first_scope.session, run.run.id)
    assert summary.observations == []
    assert summary.run.aggregate_state == "running"
  end

  test "direct observation creates reject foreign work runs" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Observation Direct Scope A",
        workspace_slug: "observation-direct-scope-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Observation Direct Scope B",
        workspace_slug: "observation-direct-scope-b"
      )

    {:ok, verification_check} = create_required_verification_check(first_scope.session)
    {:ok, foreign_check} = create_required_verification_check(second_scope.session)
    {:ok, foreign_run} = create_ready_run(second_scope.session, foreign_check)

    {:ok, operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "direct-foreign-run-observation"
      )

    assert {:error, error} =
             Ash.create(
               ExecutionObservation,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: first_scope.session.organization_id,
                 workspace_id: first_scope.session.workspace_id,
                 work_run_id: foreign_run.run.id,
                 operation_id: operation.id,
                 verification_check_id: verification_check.id,
                 graph_item_id: verification_check.graph_item_id,
                 source_kind: "human",
                 source_identity: "manual:direct-foreign-run-observation",
                 idempotency_key: "direct-foreign-run-observation",
                 observed_status: "passed",
                 normalized_status: "succeeded",
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 rationale: "Direct creates must not link foreign runs.",
                 metadata: %{}
               },
               actor: first_scope.session,
               action: :create
             )

    assert Exception.message(error) =~ "work_run_id"
  end

  test "direct observation creates reject checks outside the run packet contract" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, required_check} = create_required_verification_check(bootstrap.session)
    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, required_check)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "direct-unrequired-check-observation"
      )

    assert {:error, error} =
             Ash.create(
               ExecutionObservation,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 work_run_id: run_result.run.id,
                 operation_id: operation.id,
                 verification_check_id: unrelated_check.id,
                 graph_item_id: unrelated_check.graph_item_id,
                 source_kind: "human",
                 source_identity: "manual:direct-unrequired-check-observation",
                 idempotency_key: "direct-unrequired-check-observation",
                 observed_status: "passed",
                 normalized_status: "succeeded",
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 rationale: "Direct creates must not attach unrelated checks.",
                 metadata: %{}
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "verification_check_id"
  end

  test "direct observation creates reject graph-only rows outside the run packet contract" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, required_check} = create_required_verification_check(bootstrap.session)
    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, required_check)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "direct-unrelated-graph-observation"
      )

    assert {:error, error} =
             Ash.create(
               ExecutionObservation,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 work_run_id: run_result.run.id,
                 operation_id: operation.id,
                 graph_item_id: unrelated_check.graph_item_id,
                 source_kind: "human",
                 source_identity: "manual:direct-unrelated-graph-observation",
                 idempotency_key: "direct-unrelated-graph-observation",
                 observed_status: "passed",
                 normalized_status: "succeeded",
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 rationale: "Direct creates must not attach unrelated graph items.",
                 metadata: %{}
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "graph_item_id"
  end

  test "direct observation creates reject caller supplied ingestion time" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "direct-observation-rejects-ingested-at"
      )

    assert {:error, error} =
             Ash.create(
               ExecutionObservation,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 work_run_id: run_result.run.id,
                 operation_id: operation.id,
                 verification_check_id: verification_check.id,
                 graph_item_id: verification_check.graph_item_id,
                 source_kind: "human",
                 source_identity: "manual:direct-observation-rejects-ingested-at",
                 idempotency_key: "direct-observation-rejects-ingested-at",
                 observed_status: "passed",
                 normalized_status: "succeeded",
                 ingested_at: DateTime.add(DateTime.utc_now(), -3600, :second),
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 rationale: "Direct creates cannot spoof ingestion time.",
                 metadata: %{}
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "No such input `ingested_at`"
  end

  test "direct evidence candidate creates reject checks outside the run packet contract" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, required_check} = create_required_verification_check(bootstrap.session)
    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, required_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, required_check,
        key: "direct-candidate-unrequired-check"
      )

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "direct-candidate-unrequired-check"
      )

    assert {:error, error} =
             Ash.create(
               EvidenceCandidate,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 verification_check_id: unrelated_check.id,
                 work_run_id: run_result.run.id,
                 execution_observation_id: observation_result.observation.id,
                 operation_id: operation.id,
                 claim: "Direct candidate should not escape run contract.",
                 source_kind: "human",
                 source_identity: "manual:direct-candidate-unrequired-check",
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 sensitivity: "internal"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "verification_check_id"
  end

  test "direct evidence candidate creates derive candidate state" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "direct-candidate-derived-state"
      )

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "direct-candidate-derived-state"
      )

    assert {:ok, candidate} =
             Ash.create(
               EvidenceCandidate,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 verification_check_id: verification_check.id,
                 work_run_id: run_result.run.id,
                 execution_observation_id: observation_result.observation.id,
                 operation_id: operation.id,
                 claim: "Direct candidate should derive state.",
                 source_kind: "human",
                 source_identity: "manual:direct-candidate-derived-state",
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 sensitivity: "internal"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert candidate.candidate_state == "candidate"
    assert is_nil(candidate.rejection_reason)
  end

  test "direct evidence candidate creates reject non-candidate operations" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "direct-candidate-wrong-operation"
      )

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "direct-candidate-wrong-operation"
      )

    assert {:error, error} =
             Ash.create(
               EvidenceCandidate,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 verification_check_id: verification_check.id,
                 work_run_id: run_result.run.id,
                 execution_observation_id: observation_result.observation.id,
                 operation_id: operation.id,
                 claim: "Direct candidate should require candidate operations.",
                 source_kind: "human",
                 source_identity: "manual:direct-candidate-wrong-operation",
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 sensitivity: "internal"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "operation_id"
  end

  test "run summaries ignore malformed cross-scope observation rows" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Observation Summary Scope A",
        workspace_slug: "observation-summary-scope-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Observation Summary Scope B",
        workspace_slug: "observation-summary-scope-b"
      )

    {:ok, verification_check} = create_required_verification_check(first_scope.session)
    {:ok, foreign_check} = create_required_verification_check(second_scope.session)
    {:ok, foreign_run} = create_ready_run(second_scope.session, foreign_check)

    {:ok, operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "malformed-summary-observation"
      )

    observation_id =
      insert_malformed_execution_observation!(
        first_scope.session,
        operation,
        foreign_run.run,
        verification_check
      )

    assert {:ok, summary} = Runs.get_summary(second_scope.session, foreign_run.run.id)
    refute Enum.any?(summary.observations, &(&1.id == observation_id))
  end

  test "failed observations mark the work run failed" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "failed-observation",
        observed_status: "failed",
        normalized_status: "failed"
      )

    assert observation_result.observation.normalized_status == "failed"
    assert observation_result.run.aggregate_state == "failed"
    assert observation_result.run.execution_state == "failed"
    assert observation_result.run.verification_state == "failed"
  end

  test "succeeded observations do not resurrect a run with failed observations" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, [first_check, second_check])

    {:ok, failed_observation} =
      record_observation(bootstrap.session, run_result.run, first_check,
        key: "failed-then-success-first",
        observed_status: "failed",
        normalized_status: "failed"
      )

    assert failed_observation.run.aggregate_state == "failed"

    {:ok, succeeded_observation} =
      record_observation(bootstrap.session, failed_observation.run, second_check,
        key: "failed-then-success-second"
      )

    assert succeeded_observation.run.aggregate_state == "failed"
    assert succeeded_observation.run.execution_state == "failed"
    assert succeeded_observation.run.verification_state == "failed"

    {:ok, summary} = Runs.get_summary(bootstrap.session, run_result.run.id)
    assert summary.run.aggregate_state == "failed"
    assert summary.run.execution_state == "failed"
    assert summary.run.verification_state == "failed"
  end

  test "passed evidence from a failed observation cannot satisfy or verify a run" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "failed-observation-passed-evidence",
        observed_status: "failed",
        normalized_status: "failed"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "failed-observation-passed-evidence"
      )

    observation_id = observation_result.observation.id

    assert {:error, {:observation_not_successful, ^observation_id}} =
             accept_candidate(bootstrap.session, candidate,
               key: "failed-observation-passed-evidence",
               result: "passed"
             )

    {:ok, summary} = Runs.get_summary(bootstrap.session, run_result.run.id)
    assert summary.run.aggregate_state == "failed"
    assert summary.run.verification_state == "failed"
    assert [%{state: "pending"}] = summary.required_checks
    assert summary.evidence_items == []
    assert summary.verification_results == []
  end

  test "passed evidence rejects stale or unauthenticated observations" do
    cases = [
      {"stale-observation-evidence", "stale", "owner_attested"},
      {"unauthenticated-observation-evidence", "fresh", "unauthenticated"}
    ]

    for {key, freshness_state, trust_basis} <- cases do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      {:ok, verification_check} = create_required_verification_check(bootstrap.session)
      {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

      {:ok, observation_result} =
        record_observation(bootstrap.session, run_result.run, verification_check,
          key: key,
          freshness_state: freshness_state,
          trust_basis: trust_basis
        )

      {:ok, candidate} =
        create_evidence_candidate(
          bootstrap.session,
          run_result.run,
          verification_check,
          observation_result.observation,
          key: key,
          freshness_state: freshness_state,
          trust_basis: trust_basis
        )

      observation_id = observation_result.observation.id

      assert {:error, {:observation_not_acceptable_evidence, ^observation_id}} =
               accept_candidate(bootstrap.session, candidate, key: key, result: "passed")

      {:ok, summary} = Runs.get_summary(bootstrap.session, run_result.run.id)
      assert [%{state: "pending"}] = summary.required_checks
      assert summary.evidence_items == []
      assert summary.verification_results == []
    end
  end

  test "verified runs stay verified after later successful observations" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "verified-before-extra-observation"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        observation_result.run,
        verification_check,
        observation_result.observation,
        key: "verified-before-extra-observation"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate,
        key: "verified-before-extra-observation",
        result: "passed"
      )

    assert accepted.work_run.aggregate_state == "verified"
    assert accepted.work_run.verification_state == "verified"

    {:ok, later_observation} =
      record_observation(bootstrap.session, accepted.work_run, verification_check,
        key: "verified-after-extra-observation"
      )

    assert later_observation.run.aggregate_state == "verified"
    assert later_observation.run.execution_state == "completed"
    assert later_observation.run.verification_state == "verified"

    {:ok, summary} = Runs.get_summary(bootstrap.session, accepted.work_run.id)
    assert summary.run.aggregate_state == "verified"
    assert summary.run.execution_state == "completed"
    assert summary.run.verification_state == "verified"
  end

  test "later failed observations invalidate verified runs" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "verified-before-late-failed-observation"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        observation_result.run,
        verification_check,
        observation_result.observation,
        key: "verified-before-late-failed-observation"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate,
        key: "verified-before-late-failed-observation",
        result: "passed"
      )

    assert accepted.work_run.aggregate_state == "verified"
    assert accepted.work_run.verification_state == "verified"

    {:ok, later_observation} =
      record_observation(bootstrap.session, accepted.work_run, verification_check,
        key: "verified-after-late-failed-observation",
        normalized_status: "failed",
        observed_status: "failed"
      )

    assert later_observation.run.aggregate_state == "failed"
    assert later_observation.run.execution_state == "failed"
    assert later_observation.run.verification_state == "failed"

    {:ok, summary} = Runs.get_summary(bootstrap.session, accepted.work_run.id)
    assert summary.run.aggregate_state == "failed"
    assert summary.run.execution_state == "failed"
    assert summary.run.verification_state == "failed"
  end

  test "verified runs reject stale failed evidence acceptance" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, stale_observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "stale-candidate-before-verification"
      )

    {:ok, stale_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        stale_observation_result.run,
        verification_check,
        stale_observation_result.observation,
        key: "stale-candidate-before-verification"
      )

    {:ok, passed_observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "passed-candidate-verifies-before-stale-failed"
      )

    {:ok, passed_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        passed_observation_result.run,
        verification_check,
        passed_observation_result.observation,
        key: "passed-candidate-verifies-before-stale-failed"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, passed_candidate,
        key: "passed-candidate-verifies-before-stale-failed",
        result: "passed"
      )

    assert accepted.work_run.aggregate_state == "verified"
    assert accepted.work_run.verification_state == "verified"

    run_id = accepted.work_run.id

    check_id = verification_check.id

    assert {:error, {:verification_result_slot_conflict, ^run_id, ^check_id}} =
             accept_candidate(bootstrap.session, stale_candidate,
               key: "stale-failed-candidate-after-verification",
               result: "failed"
             )

    refute accepted_evidence_for_candidate?(stale_candidate.id)

    {:ok, summary} = Runs.get_summary(bootstrap.session, accepted.work_run.id)
    assert summary.run.aggregate_state == "verified"
    assert summary.run.execution_state == "completed"
    assert summary.run.verification_state == "verified"
  end

  test "direct verification completion records decision metadata" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :verification_complete,
        idempotency_key: "direct-completion-decision-metadata"
      )

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               operation,
               verification_check,
               %{
                 title: "Direct completion evidence",
                 body: "Direct completion evidence body.",
                 artifact_uri: "https://example.test/direct-completion"
               }
             )

    assert completed.verification_result.work_run_id == nil
    assert completed.verification_result.work_packet_version_id == nil
    assert completed.verification_result.target_graph_item_id == verification_check.graph_item_id
    assert completed.verification_result.actor_principal_id == bootstrap.session.principal_id
    assert completed.verification_result.policy_basis == "verification_complete"
    assert completed.verification_result.recorded_at != nil
  end

  test "runless evidence candidates can be accepted without updating a work run" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, candidate_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "runless-candidate"
      )

    assert {:ok, candidate} =
             Verification.create_evidence_candidate(bootstrap.session, candidate_operation, %{
               verification_check_id: verification_check.id,
               claim: "Runless evidence candidate.",
               source_kind: "human_note",
               source_identity: "manual:runless-candidate",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               sensitivity: "internal"
             })

    assert candidate.work_run_id == nil
    assert candidate.execution_observation_id == nil

    {:ok, acceptance_operation} =
      Operations.start_operation(bootstrap.session, :evidence_accept,
        idempotency_key: "runless-candidate-accept"
      )

    assert {:ok, accepted} =
             Verification.accept_evidence_candidate(
               bootstrap.session,
               acceptance_operation,
               candidate,
               %{
                 title: "Runless accepted evidence",
                 body: "This evidence is not attached to a work run.",
                 result: "passed",
                 acceptance_policy_basis: "owner_acceptance"
               }
             )

    assert accepted.evidence_item.candidate_id == candidate.id
    assert accepted.evidence_item.work_run_id == nil
    assert accepted.verification_result.work_run_id == nil
    assert accepted.verification_result.work_packet_version_id == nil
    assert accepted.verification_result.target_graph_item_id == verification_check.graph_item_id
    assert accepted.work_run == nil
    assert accepted.candidate.candidate_state == "accepted"

    {:ok, satisfied_check} =
      WorkGraph.get_verification_check(bootstrap.session, verification_check.id)

    assert satisfied_check.lifecycle_state == "satisfied"

    accepted_attrs = %{
      title: "Runless accepted evidence",
      body: "This evidence is not attached to a work run.",
      result: "passed",
      acceptance_policy_basis: "owner_acceptance"
    }

    assert {:ok, replayed} =
             Verification.accept_evidence_candidate(
               bootstrap.session,
               acceptance_operation,
               candidate,
               accepted_attrs
             )

    assert replayed.evidence_item.id == accepted.evidence_item.id
    assert replayed.verification_result.id == accepted.verification_result.id
    assert replayed.work_run == nil

    {:ok, summary} = Runs.get_summary(bootstrap.session, run_result.run.id)
    assert [%{state: "pending"}] = summary.required_checks
    assert [%{reason: "missing_accepted_evidence"}] = summary.missing_evidence
  end

  test "passed acceptance identifies a missing run-required check by run context" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "missing-acceptance-required-check"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "missing-acceptance-required-check"
      )

    delete_run_required_check!(run_result.run.id, verification_check.id)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :evidence_accept,
        idempotency_key: "missing-acceptance-required-check"
      )

    missing_context = %{
      run_id: run_result.run.id,
      verification_check_id: verification_check.id
    }

    assert {:error, {:not_found, RunRequiredCheck, ^missing_context}} =
             Verification.accept_evidence_candidate(
               bootstrap.session,
               operation,
               candidate,
               %{
                 title: "Missing required-check evidence",
                 body: "The run-required check row is missing.",
                 result: "passed",
                 acceptance_policy_basis: "owner_acceptance"
               }
             )
  end

  test "graph-only observations can back matching evidence candidates" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "graph-only-candidate-observation"
      )

    assert {:ok, observation_result} =
             Runs.record_observation(bootstrap.session, observation_operation, run_result.run, %{
               source_kind: "human",
               source_identity: "manual:graph-only-candidate-observation",
               idempotency_key: "graph-only-candidate-observation",
               observed_status: "passed",
               normalized_status: "succeeded",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               graph_item_id: verification_check.graph_item_id,
               rationale: "Graph item identifies the required check."
             })

    assert observation_result.observation.verification_check_id == nil

    {:ok, candidate_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "graph-only-candidate-observation"
      )

    assert {:ok, candidate} =
             Verification.create_evidence_candidate(bootstrap.session, candidate_operation, %{
               work_run_id: run_result.run.id,
               verification_check_id: verification_check.id,
               execution_observation_id: observation_result.observation.id,
               claim: "Graph-only observations can become candidates.",
               source_kind: "human",
               source_identity: "manual:graph-only-candidate-observation",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               sensitivity: "internal"
             })

    assert candidate.execution_observation_id == observation_result.observation.id
    assert candidate.verification_check_id == verification_check.id
  end

  test "evidence candidate operation replay rejects changed candidate input" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "candidate-operation-input-conflict"
      )

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "candidate-operation-input-conflict"
      )

    attrs = %{
      work_run_id: run_result.run.id,
      verification_check_id: verification_check.id,
      execution_observation_id: observation_result.observation.id,
      claim: "Candidate operation replay input.",
      source_kind: "human",
      source_identity: "manual:candidate-operation-input-conflict",
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      sensitivity: "internal"
    }

    assert {:ok, candidate} =
             Verification.create_evidence_candidate(bootstrap.session, operation, attrs)

    {:ok, replay_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "candidate-operation-input-conflict"
      )

    candidate_id = candidate.id

    assert {:error, {:evidence_candidate_operation_conflict, ^candidate_id}} =
             Verification.create_evidence_candidate(
               bootstrap.session,
               replay_operation,
               %{attrs | claim: "Changed candidate claim."}
             )
  end

  test "evidence acceptance operation replay rejects changed acceptance input" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "acceptance-operation-input-conflict",
        normalized_status: "failed",
        observed_status: "failed"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "acceptance-operation-input-conflict"
      )

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :evidence_accept,
        idempotency_key: "acceptance-operation-input-conflict"
      )

    assert {:ok, accepted} =
             Verification.accept_evidence_candidate(bootstrap.session, operation, candidate, %{
               title: "Failed accepted evidence",
               body: "The provider reported a failed result.",
               result: "failed",
               acceptance_policy_basis: "owner_acceptance"
             })

    {:ok, replay_operation} =
      Operations.start_operation(bootstrap.session, :evidence_accept,
        idempotency_key: "acceptance-operation-input-conflict"
      )

    evidence_item_id = accepted.evidence_item.id

    assert {:error, {:evidence_acceptance_operation_conflict, ^evidence_item_id}} =
             Verification.accept_evidence_candidate(
               bootstrap.session,
               replay_operation,
               candidate,
               %{
                 title: "Passed accepted evidence",
                 body: "The provider corrected the result.",
                 result: "passed",
                 acceptance_policy_basis: "owner_acceptance"
               }
             )
  end

  test "accepted evidence candidates reject new acceptance operations" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "accepted-candidate-new-operation",
        normalized_status: "failed",
        observed_status: "failed"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "accepted-candidate-new-operation"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate,
        key: "accepted-candidate-first-operation",
        result: "failed"
      )

    assert accepted.candidate.candidate_state == "accepted"
    candidate_id = candidate.id

    assert {:error, {:evidence_candidate_already_accepted, ^candidate_id}} =
             accept_candidate(bootstrap.session, candidate,
               key: "accepted-candidate-second-operation",
               result: "failed"
             )
  end

  test "runless evidence completion propagates to parent graph items" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, graph} = create_required_verification_graph(bootstrap.session)

    {:ok, candidate_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "runless-parent-completion-candidate"
      )

    assert {:ok, candidate} =
             Verification.create_evidence_candidate(bootstrap.session, candidate_operation, %{
               verification_check_id: graph.verification_check.id,
               claim: "Runless evidence candidate.",
               source_kind: "human_note",
               source_identity: "manual:runless-parent-completion",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               sensitivity: "internal"
             })

    {:ok, acceptance_operation} =
      Operations.start_operation(bootstrap.session, :evidence_accept,
        idempotency_key: "runless-parent-completion-accept"
      )

    assert {:ok, accepted} =
             Verification.accept_evidence_candidate(
               bootstrap.session,
               acceptance_operation,
               candidate,
               %{
                 title: "Runless accepted evidence",
                 body: "This evidence is not attached to a work run.",
                 result: "passed",
                 acceptance_policy_basis: "owner_acceptance"
               }
             )

    assert accepted.work_run == nil

    assert "satisfied" ==
             fetch_resource!(WorkGraph.VerificationCheck, graph.verification_check.id).lifecycle_state

    assert "verified_complete" ==
             fetch_resource!(ReviewFinding, graph.review_finding.id).lifecycle_state

    assert "verified_complete" == fetch_resource!(Task, graph.task.id).lifecycle_state
  end

  test "runless failed evidence is rejected before consuming the check result slot" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, candidate_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "runless-failed-candidate"
      )

    assert {:ok, candidate} =
             Verification.create_evidence_candidate(bootstrap.session, candidate_operation, %{
               verification_check_id: verification_check.id,
               claim: "Runless failed evidence candidate.",
               source_kind: "human_note",
               source_identity: "manual:runless-failed-candidate",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               sensitivity: "internal"
             })

    candidate_id = candidate.id

    assert {:error, {:runless_evidence_result_not_passed, ^candidate_id}} =
             accept_candidate(bootstrap.session, candidate,
               key: "runless-failed-candidate",
               result: "failed"
             )

    {:ok, required_check} =
      WorkGraph.get_verification_check(bootstrap.session, verification_check.id)

    assert required_check.lifecycle_state == "required"

    assert {:ok, accepted} =
             accept_candidate(bootstrap.session, candidate,
               key: "runless-failed-candidate-passed",
               result: "passed"
             )

    assert accepted.verification_result.result == "passed"
    assert accepted.work_run == nil

    {:ok, satisfied_check} =
      WorkGraph.get_verification_check(bootstrap.session, verification_check.id)

    assert satisfied_check.lifecycle_state == "satisfied"
  end

  test "work run verifies only after every required check has passing evidence" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, [first_check, second_check])

    {:ok, first_observation} =
      record_observation(bootstrap.session, run_result.run, first_check, key: "first-check")

    {:ok, first_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        first_check,
        first_observation.observation,
        key: "first-check"
      )

    {:ok, first_accepted} =
      accept_candidate(bootstrap.session, first_candidate, key: "first-check", result: "passed")

    assert first_accepted.work_run.aggregate_state == "awaiting_verification"

    {:ok, partial_summary} = Runs.get_summary(bootstrap.session, run_result.run.id)

    second_check_id = second_check.id

    assert [%{verification_check_id: ^second_check_id, reason: "missing_accepted_evidence"}] =
             partial_summary.missing_evidence

    {:ok, second_observation} =
      record_observation(bootstrap.session, first_accepted.work_run, second_check,
        key: "second-check"
      )

    {:ok, second_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        first_accepted.work_run,
        second_check,
        second_observation.observation,
        key: "second-check"
      )

    {:ok, second_accepted} =
      accept_candidate(bootstrap.session, second_candidate, key: "second-check", result: "passed")

    assert second_accepted.work_run.aggregate_state == "verified"
    assert second_accepted.work_run.verification_state == "verified"
  end

  test "failed evidence result does not satisfy a required check" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check)

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "failed-evidence"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate, key: "failed-evidence", result: "failed")

    assert accepted.verification_result.result == "failed"
    assert accepted.work_run.aggregate_state == "failed"

    assert {:ok, [required_check]} = Runs.required_checks_for_run(run_result.run.id)
    assert required_check.state == "pending"
  end

  test "every duplicate result combination returns the stable slot conflict without partial evidence" do
    for {first_result, second_result} <- [
          {"passed", "passed"},
          {"passed", "failed"},
          {"failed", "passed"},
          {"failed", "failed"}
        ] do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      {:ok, verification_check} = create_required_verification_check(bootstrap.session)
      {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)
      key = "duplicate-result-slot-#{first_result}-#{second_result}"

      {:ok, observation_result} =
        record_observation(bootstrap.session, run_result.run, verification_check, key: key)

      {:ok, first_candidate} =
        create_evidence_candidate(
          bootstrap.session,
          run_result.run,
          verification_check,
          observation_result.observation,
          key: "#{key}-first"
        )

      {:ok, second_candidate} =
        create_evidence_candidate(
          bootstrap.session,
          run_result.run,
          verification_check,
          observation_result.observation,
          key: "#{key}-second"
        )

      assert {:ok, _accepted} =
               accept_candidate(bootstrap.session, first_candidate,
                 key: "#{key}-first",
                 result: first_result
               )

      run_id = run_result.run.id
      check_id = verification_check.id

      assert {:error, {:verification_result_slot_conflict, ^run_id, ^check_id}} =
               accept_candidate(bootstrap.session, second_candidate,
                 key: "#{key}-second",
                 result: second_result
               )

      refute accepted_evidence_for_candidate?(second_candidate.id)

      assert 1 ==
               VerificationResult
               |> Ash.Query.filter(work_run_id == ^run_id and verification_check_id == ^check_id)
               |> Ash.read!(authorize?: false)
               |> length()
    end
  end

  test "a result for a different check preserves terminal run validation" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, [first_check, second_check])

    {:ok, first_observation} =
      record_observation(bootstrap.session, run_result.run, first_check,
        key: "different-slot-first"
      )

    {:ok, second_observation} =
      record_observation(bootstrap.session, first_observation.run, second_check,
        key: "different-slot-second"
      )

    {:ok, first_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        second_observation.run,
        first_check,
        first_observation.observation,
        key: "different-slot-first"
      )

    {:ok, second_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        second_observation.run,
        second_check,
        second_observation.observation,
        key: "different-slot-second"
      )

    assert {:ok, accepted} =
             accept_candidate(bootstrap.session, first_candidate,
               key: "different-slot-first",
               result: "failed"
             )

    run_id = accepted.work_run.id

    assert {:error, {:work_run_already_failed, ^run_id}} =
             accept_candidate(bootstrap.session, second_candidate,
               key: "different-slot-second",
               result: "passed"
             )

    refute accepted_evidence_for_candidate?(second_candidate.id)
  end

  test "unknown evidence results are rejected before accepting a candidate" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "unknown-evidence-result"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "unknown-evidence-result"
      )

    assert {:error, {:invalid_evidence_result, "passsed"}} =
             accept_candidate(bootstrap.session, candidate,
               key: "unknown-evidence-result",
               result: "passsed"
             )

    refute accepted_evidence_for_candidate?(candidate.id)
    refute verification_result_for_candidate_target?(candidate)
  end

  test "satisfied verification check rejects passed acceptance from separate work runs" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, first_run} = create_ready_run(bootstrap.session, verification_check)
    {:ok, second_run} = create_ready_run(bootstrap.session, verification_check)

    {:ok, first_observation} =
      record_observation(bootstrap.session, first_run.run, verification_check, key: "rerun-first")

    {:ok, first_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        first_run.run,
        verification_check,
        first_observation.observation,
        key: "rerun-first"
      )

    {:ok, first_accepted} =
      accept_candidate(bootstrap.session, first_candidate, key: "rerun-first", result: "passed")

    {:ok, second_observation} =
      record_observation(bootstrap.session, second_run.run, verification_check,
        key: "rerun-second"
      )

    {:ok, second_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        second_run.run,
        verification_check,
        second_observation.observation,
        key: "rerun-second"
      )

    assert {:error, {:invalid_verification_check_status, verification_check_id}} =
             accept_candidate(bootstrap.session, second_candidate,
               key: "rerun-second",
               result: "passed"
             )

    assert verification_check_id == verification_check.id
    assert first_accepted.verification_result.verification_check_id == verification_check.id

    assert first_accepted.work_run.aggregate_state == "verified"
    assert fetch_resource!(Run, second_run.run.id).aggregate_state == "awaiting_verification"
  end

  test "candidate observations must belong to the candidate run and check" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, first_run} = create_ready_run(bootstrap.session, [first_check, second_check])
    {:ok, second_run} = create_ready_run(bootstrap.session, first_check)

    {:ok, second_run_observation} =
      record_observation(bootstrap.session, second_run.run, first_check, key: "second-run")

    {:ok, first_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "wrong-run-observation-candidate"
      )

    second_run_observation_id = second_run_observation.observation.id

    assert {:error, {:observation_not_for_candidate_run, ^second_run_observation_id}} =
             Verification.create_evidence_candidate(bootstrap.session, first_operation, %{
               work_run_id: first_run.run.id,
               verification_check_id: first_check.id,
               execution_observation_id: second_run_observation.observation.id,
               claim: "Wrong run observation.",
               source_kind: "human",
               source_identity: "manual:wrong-run",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               sensitivity: "internal"
             })

    {:ok, first_run_observation} =
      record_observation(bootstrap.session, first_run.run, first_check, key: "first-run")

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "wrong-check-observation-candidate"
      )

    first_run_observation_id = first_run_observation.observation.id

    assert {:error, {:observation_not_for_candidate_run, ^first_run_observation_id}} =
             Verification.create_evidence_candidate(bootstrap.session, second_operation, %{
               work_run_id: first_run.run.id,
               verification_check_id: second_check.id,
               execution_observation_id: first_run_observation.observation.id,
               claim: "Wrong check observation.",
               source_kind: "human",
               source_identity: "manual:wrong-check",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               sensitivity: "internal"
             })
  end

  test "candidate artifact references must stay in scope" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Candidate Artifact A",
        workspace_slug: "candidate-artifact-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Candidate Artifact B",
        workspace_slug: "candidate-artifact-b"
      )

    {:ok, verification_check} = create_required_verification_check(first_scope.session)
    {:ok, run_result} = create_ready_run(first_scope.session, verification_check)

    {:ok, observation_result} =
      record_observation(first_scope.session, run_result.run, verification_check)

    foreign_artifact = insert_artifact!(second_scope, "Foreign evidence artifact")

    {:ok, operation} =
      Operations.start_operation(first_scope.session, :evidence_candidate_create,
        idempotency_key: "cross-scope-artifact-candidate"
      )

    assert {:error, :forbidden} =
             Verification.create_evidence_candidate(first_scope.session, operation, %{
               work_run_id: run_result.run.id,
               verification_check_id: verification_check.id,
               execution_observation_id: observation_result.observation.id,
               artifact_id: foreign_artifact.id,
               claim: "Cross-scope artifact.",
               source_kind: "human",
               source_identity: "manual:cross-scope-artifact",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               sensitivity: "internal"
             })
  end

  test "observation recording is idempotent for the same source key" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    attrs = %{
      source_kind: "provider_check",
      source_identity: "provider:test",
      idempotency_key: "provider-check:123",
      observed_status: "success",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Provider check succeeded."
    }

    {:ok, first_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-operation"
      )

    assert {:ok, first} =
             Runs.record_observation(bootstrap.session, first_operation, run_result.run, attrs)

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-operation"
      )

    assert {:ok, second} =
             Runs.record_observation(bootstrap.session, second_operation, run_result.run, attrs)

    assert second.observation.id == first.observation.id
  end

  test "blank observation idempotency keys are stored as nil and do not replay" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    attrs = %{
      source_kind: "provider_check",
      source_identity: "provider:blank-idempotency-key",
      idempotency_key: "",
      observed_status: "success",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Provider check succeeded without a replay key."
    }

    {:ok, first_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "blank-idempotency-key:first"
      )

    assert {:ok, first} =
             Runs.record_observation(bootstrap.session, first_operation, run_result.run, attrs)

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "blank-idempotency-key:second"
      )

    assert {:ok, second} =
             Runs.record_observation(bootstrap.session, second_operation, run_result.run, attrs)

    assert first.observation.id != second.observation.id
    assert first.observation.idempotency_key == nil
    assert second.observation.idempotency_key == nil

    {:ok, summary} = Runs.get_summary(bootstrap.session, run_result.run.id)
    assert length(summary.observations) == 2
  end

  test "observation operation replay rejects changed observation fields" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    attrs = %{
      source_kind: "provider_check",
      source_identity: "provider:operation-replay",
      idempotency_key: "provider-check:operation-replay:first",
      observed_status: "success",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Provider check succeeded."
    }

    {:ok, first_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-operation-replay"
      )

    assert {:ok, first} =
             Runs.record_observation(bootstrap.session, first_operation, run_result.run, attrs)

    {:ok, replay_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-operation-replay"
      )

    first_observation_id = first.observation.id

    assert {:error, {:observation_operation_conflict, ^first_observation_id}} =
             Runs.record_observation(bootstrap.session, replay_operation, run_result.run, %{
               attrs
               | source_identity: "provider:operation-replay-changed",
                 idempotency_key: "provider-check:operation-replay:changed"
             })
  end

  test "observation idempotency rejects conflicting check replays on the same run" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, [first_check, second_check])

    attrs = %{
      source_kind: "provider_check",
      source_identity: "provider:conflicting-replay",
      idempotency_key: "provider-check:conflicting-replay",
      observed_status: "success",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      verification_check_id: first_check.id,
      graph_item_id: first_check.graph_item_id,
      rationale: "Provider check succeeded."
    }

    {:ok, first_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-conflicting-replay-first"
      )

    assert {:ok, first} =
             Runs.record_observation(bootstrap.session, first_operation, run_result.run, attrs)

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-conflicting-replay-second"
      )

    first_observation_id = first.observation.id

    assert {:error, {:observation_idempotency_conflict, ^first_observation_id}} =
             Runs.record_observation(
               bootstrap.session,
               second_operation,
               run_result.run,
               %{
                 attrs
                 | verification_check_id: second_check.id,
                   graph_item_id: second_check.graph_item_id
               }
             )
  end

  test "observation idempotency rejects conflicting evidence trust replays" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    attrs = %{
      source_kind: "provider_check",
      source_identity: "provider:trust-conflict",
      idempotency_key: "provider-check:trust-conflict",
      observed_status: "success",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Provider check succeeded."
    }

    {:ok, first_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-trust-conflict-first"
      )

    assert {:ok, first} =
             Runs.record_observation(bootstrap.session, first_operation, run_result.run, attrs)

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-trust-conflict-second"
      )

    first_observation_id = first.observation.id

    assert {:error, {:observation_idempotency_conflict, ^first_observation_id}} =
             Runs.record_observation(
               bootstrap.session,
               second_operation,
               run_result.run,
               %{attrs | freshness_state: "stale"}
             )
  end

  test "observation recording reloads the persisted run before writing" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Observation Reload A",
        workspace_slug: "observation-reload-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Observation Reload B",
        workspace_slug: "observation-reload-b"
      )

    {:ok, verification_check} = create_required_verification_check(second_scope.session)
    {:ok, second_run} = create_ready_run(second_scope.session, verification_check)

    spoofed_run = %{
      second_run.run
      | organization_id: first_scope.session.organization_id,
        workspace_id: first_scope.session.workspace_id
    }

    {:ok, operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "spoofed-run-observation"
      )

    assert {:error, :forbidden} =
             Runs.record_observation(first_scope.session, operation, spoofed_run, %{
               source_kind: "human",
               source_identity: "manual:spoofed-run-observation",
               idempotency_key: "spoofed-run-observation",
               observed_status: "passed",
               normalized_status: "succeeded",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               rationale: "Spoofed in-memory run structs are rejected."
             })
  end
end
