defmodule OfficeGraph.WorkPackets.WorkPacketRunVerificationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkGraph.{Artifact, GraphItem, ReviewFinding, Task}
  alias OfficeGraph.WorkPackets

  require Ash.Query

  test "packet-backed work run stays unverified until evidence is accepted" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-flow"
      )

    assert {:ok, packet_result} =
             WorkPackets.create_packet(bootstrap.session, packet_operation, %{
               title: "Verify launch readiness",
               objective: "Confirm launch checklist has passing evidence.",
               context_summary: "Launch work collected from the current work graph.",
               requirements: "Review launch blockers and resolve open verification checks.",
               success_criteria: "The required verification check has accepted evidence.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [verification_check.graph_item_id],
               verification_check_ids: [verification_check.id]
             })

    assert packet_result.packet.title == "Verify launch readiness"
    assert packet_result.packet.state == "ready"
    assert packet_result.version.version_number == 1
    assert packet_result.version.lifecycle_state == "ready"
    assert packet_result.version.operation_id == packet_operation.id

    assert Enum.map(packet_result.required_checks, & &1.verification_check_id) == [
             verification_check.id
           ]

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "packet-flow-run"
      )

    assert {:ok, run_result} =
             Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
               source_surface: "test",
               reason: "Execute accepted packet.",
               authority_posture: "human_supervised"
             })

    assert run_result.run.work_packet_id == packet_result.packet.id
    assert run_result.run.work_packet_version_id == packet_result.version.id
    assert run_result.run.aggregate_state == "running"
    assert run_result.run.execution_state == "pending"
    assert run_result.run.verification_state == "unverified"

    assert Enum.map(run_result.required_checks, & &1.verification_check_id) == [
             verification_check.id
           ]

    {:ok, observation_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "packet-flow-observation"
      )

    assert {:ok, observation_result} =
             Runs.record_observation(bootstrap.session, observation_operation, run_result.run, %{
               source_kind: "human",
               source_identity: "manual:test",
               idempotency_key: "observation:launch-check",
               observed_status: "passed",
               normalized_status: "succeeded",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               verification_check_id: verification_check.id,
               graph_item_id: verification_check.graph_item_id,
               rationale: "Human confirmed the launch check passed."
             })

    assert observation_result.observation.normalized_status == "succeeded"
    assert observation_result.run.verification_state == "missing_evidence"
    assert observation_result.run.aggregate_state == "awaiting_verification"

    {:ok, candidate_operation} =
      Operations.start_operation(bootstrap.session, :evidence_candidate_create,
        idempotency_key: "packet-flow-candidate"
      )

    assert {:ok, candidate} =
             Verification.create_evidence_candidate(
               bootstrap.session,
               candidate_operation,
               %{
                 work_run_id: run_result.run.id,
                 verification_check_id: verification_check.id,
                 execution_observation_id: observation_result.observation.id,
                 claim: "Launch checklist passed.",
                 source_kind: "human",
                 source_identity: "manual:test",
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 sensitivity: "internal"
               }
             )

    assert candidate.candidate_state == "candidate"

    {:ok, acceptance_operation} =
      Operations.start_operation(bootstrap.session, :evidence_accept,
        idempotency_key: "packet-flow-accept"
      )

    assert {:ok, accepted} =
             Verification.accept_evidence_candidate(
               bootstrap.session,
               acceptance_operation,
               candidate,
               %{
                 title: "Launch check passed",
                 body: "The launch checklist passed in the test provider.",
                 result: "passed",
                 acceptance_policy_basis: "owner_acceptance"
               }
             )

    assert accepted.evidence_item.state == "accepted"
    assert accepted.evidence_item.candidate_id == candidate.id
    assert accepted.evidence_item.work_run_id == run_result.run.id
    assert accepted.verification_result.work_run_id == run_result.run.id
    assert accepted.verification_result.work_packet_version_id == packet_result.version.id
    assert accepted.verification_result.result == "passed"
    assert accepted.work_run.aggregate_state == "verified"
    assert accepted.work_run.verification_state == "verified"
  end

  test "work run start rejects packet versions that are not ready" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "draft-packet"
      )

    assert {:ok, packet_result} =
             WorkPackets.create_packet(bootstrap.session, packet_operation, %{
               title: "Incomplete packet",
               objective: "Investigate incomplete packet behavior.",
               context_summary: "Missing success criteria and required checks.",
               requirements: "Find missing fields.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [],
               verification_check_ids: []
             })

    assert packet_result.version.lifecycle_state == "draft"

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "draft-packet-run"
      )

    assert {:error, {:packet_version_not_ready, packet_result.version.id}} ==
             Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
               source_surface: "test",
               reason: "Should be rejected.",
               authority_posture: "human_supervised"
             })

    stale_version = %{packet_result.version | lifecycle_state: "stale"}
    superseded_version = %{packet_result.version | lifecycle_state: "superseded"}

    assert {:error, {:packet_version_not_ready, stale_version.id}} ==
             Runs.start_run(bootstrap.session, run_operation, stale_version, %{
               source_surface: "test",
               reason: "Stale versions cannot start runs.",
               authority_posture: "human_supervised"
             })

    assert {:error, {:packet_version_not_ready, superseded_version.id}} ==
             Runs.start_run(bootstrap.session, run_operation, superseded_version, %{
               source_surface: "test",
               reason: "Superseded versions cannot start runs.",
               authority_posture: "human_supervised"
             })

    assert {:error, :missing_packet_version} ==
             Runs.start_run(bootstrap.session, run_operation, nil, %{
               source_surface: "test",
               reason: "Missing versions cannot start runs.",
               authority_posture: "human_supervised"
             })
  end

  test "work run start reloads the persisted packet version" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    spoofed_version = %{
      packet_result.version
      | lifecycle_state: "draft",
        objective: "Spoofed objective from caller memory."
    }

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "reload-persisted-packet-version"
      )

    assert {:ok, run_result} =
             Runs.start_run(bootstrap.session, run_operation, spoofed_version, %{
               source_surface: "test",
               reason: "Use persisted packet state.",
               authority_posture: "human_supervised"
             })

    assert run_result.run.objective == packet_result.version.objective
    assert run_result.run.objective != spoofed_version.objective
  end

  test "work run start rejects cross-scope packet versions" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Packet Scope A",
        workspace_slug: "packet-scope-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Packet Scope B",
        workspace_slug: "packet-scope-b"
      )

    {:ok, verification_check} = create_required_verification_check(first_scope.session)
    {:ok, run} = create_ready_run(first_scope.session, verification_check)

    {:ok, run_operation} =
      Operations.start_operation(second_scope.session, :work_run_start,
        idempotency_key: "cross-scope-run"
      )

    assert {:error, :forbidden} ==
             Runs.start_run(second_scope.session, run_operation, run.packet_version, %{
               source_surface: "test",
               reason: "Cross-scope packet should be rejected.",
               authority_posture: "human_supervised"
             })
  end

  test "evidence candidate creation and acceptance reject cross-scope references" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Evidence Scope A",
        workspace_slug: "evidence-scope-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Evidence Scope B",
        workspace_slug: "evidence-scope-b"
      )

    {:ok, verification_check} = create_required_verification_check(first_scope.session)
    {:ok, run} = create_ready_run(first_scope.session, verification_check)

    {:ok, observation_operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "cross-scope-observation"
      )

    {:ok, observation_result} =
      Runs.record_observation(first_scope.session, observation_operation, run.run, %{
        source_kind: "human",
        source_identity: "manual:cross-scope",
        idempotency_key: "cross-scope-observation",
        observed_status: "passed",
        normalized_status: "succeeded",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        verification_check_id: verification_check.id,
        graph_item_id: verification_check.graph_item_id,
        rationale: "Human confirmed the check passed."
      })

    {:ok, candidate_operation} =
      Operations.start_operation(first_scope.session, :evidence_candidate_create,
        idempotency_key: "cross-scope-candidate"
      )

    {:ok, candidate} =
      Verification.create_evidence_candidate(first_scope.session, candidate_operation, %{
        work_run_id: run.run.id,
        verification_check_id: verification_check.id,
        execution_observation_id: observation_result.observation.id,
        claim: "Cross-scope candidate.",
        source_kind: "human",
        source_identity: "manual:cross-scope",
        freshness_state: "fresh",
        trust_basis: "owner_attested",
        sensitivity: "internal"
      })

    {:ok, second_candidate_operation} =
      Operations.start_operation(second_scope.session, :evidence_candidate_create,
        idempotency_key: "cross-scope-candidate-rejected"
      )

    assert {:error, :forbidden} ==
             Verification.create_evidence_candidate(
               second_scope.session,
               second_candidate_operation,
               %{
                 work_run_id: run.run.id,
                 verification_check_id: verification_check.id,
                 execution_observation_id: observation_result.observation.id,
                 claim: "Invalid cross-scope candidate.",
                 source_kind: "human",
                 source_identity: "manual:cross-scope",
                 freshness_state: "fresh",
                 trust_basis: "owner_attested",
                 sensitivity: "internal"
               }
             )

    {:ok, acceptance_operation} =
      Operations.start_operation(second_scope.session, :evidence_accept,
        idempotency_key: "cross-scope-accept-rejected"
      )

    assert {:error, :forbidden} ==
             Verification.accept_evidence_candidate(
               second_scope.session,
               acceptance_operation,
               candidate,
               %{
                 title: "Cross-scope evidence",
                 body: "This should not be accepted.",
                 result: "passed",
                 acceptance_policy_basis: "owner_acceptance"
               }
             )
  end

  test "work packet creation returns validation errors for invalid references" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Packet Invalid Reference A",
        workspace_slug: "packet-invalid-reference-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Packet Invalid Reference B",
        workspace_slug: "packet-invalid-reference-b"
      )

    {:ok, verification_check} = create_required_verification_check(first_scope.session)
    {:ok, foreign_check} = create_required_verification_check(second_scope.session)

    assert {:error, %Ash.Error.Invalid{}} =
             create_packet_with_operation(first_scope.session, "missing-source-reference", %{
               title: "Invalid packet source",
               objective: "Reject missing source.",
               context_summary: "Invalid source reference.",
               requirements: "Use only scoped source references.",
               success_criteria: "Validation returns an error.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [Ecto.UUID.generate()],
               verification_check_ids: [verification_check.id]
             })

    assert {:error, %Ash.Error.Invalid{}} =
             create_packet_with_operation(first_scope.session, "missing-check-reference", %{
               title: "Invalid packet check",
               objective: "Reject missing check.",
               context_summary: "Invalid check reference.",
               requirements: "Use only scoped checks.",
               success_criteria: "Validation returns an error.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [verification_check.graph_item_id],
               verification_check_ids: [Ecto.UUID.generate()]
             })

    assert {:error, %Ash.Error.Invalid{}} =
             create_packet_with_operation(first_scope.session, "cross-scope-source-reference", %{
               title: "Cross-scope source",
               objective: "Reject cross-scope source.",
               context_summary: "Foreign source reference.",
               requirements: "Use only local sources.",
               success_criteria: "Validation returns an error.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [foreign_check.graph_item_id],
               verification_check_ids: [verification_check.id]
             })

    assert {:error, %Ash.Error.Invalid{}} =
             create_packet_with_operation(first_scope.session, "cross-scope-check-reference", %{
               title: "Cross-scope check",
               objective: "Reject cross-scope check.",
               context_summary: "Foreign check reference.",
               requirements: "Use only local checks.",
               success_criteria: "Validation returns an error.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [verification_check.graph_item_id],
               verification_check_ids: [foreign_check.id]
             })
  end

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

    assert {:error, :forbidden} =
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

    {:ok, unrelated_operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "unrequired-observation-reference"
      )

    run_id = run.run.id
    unrelated_check_id = unrelated_check.id
    unrelated_graph_item_id = unrelated_check.graph_item_id

    assert {:error, {:verification_check_not_required, ^run_id, ^unrelated_check_id}} =
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

    {:ok, mismatched_operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "mismatched-observation-reference"
      )

    assert {:error, {:graph_item_not_required, ^run_id, ^unrelated_graph_item_id}} =
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

    {:ok, graph_only_operation} =
      Operations.start_operation(first_scope.session, :execution_observation_record,
        idempotency_key: "unrelated-graph-only-observation-reference"
      )

    assert {:error, {:graph_item_not_required, ^run_id, ^unrelated_graph_item_id}} =
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

    {:ok, summary} = Runs.get_summary(first_scope.session, run.run.id)
    assert summary.observations == []
    assert summary.run.aggregate_state == "running"
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

    assert {:ok, replayed} =
             Verification.accept_evidence_candidate(
               bootstrap.session,
               acceptance_operation,
               candidate,
               %{
                 title: "Runless accepted evidence replay",
                 body: "Replayed runless evidence acceptance.",
                 result: "passed",
                 acceptance_policy_basis: "owner_acceptance"
               }
             )

    assert replayed.evidence_item.id == accepted.evidence_item.id
    assert replayed.verification_result.id == accepted.verification_result.id
    assert replayed.work_run == nil

    {:ok, summary} = Runs.get_summary(bootstrap.session, run_result.run.id)
    assert [%{state: "pending"}] = summary.required_checks
    assert [%{reason: "missing_accepted_evidence"}] = summary.missing_evidence
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

  test "same verification check can be verified across separate work runs" do
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

    assert {:ok, second_accepted} =
             accept_candidate(bootstrap.session, second_candidate,
               key: "rerun-second",
               result: "passed"
             )

    assert first_accepted.verification_result.verification_check_id ==
             second_accepted.verification_result.verification_check_id

    assert first_accepted.verification_result.work_run_id !=
             second_accepted.verification_result.work_run_id

    assert first_accepted.work_run.aggregate_state == "verified"
    assert second_accepted.work_run.aggregate_state == "verified"
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

  test "observation recording replays by operation before source idempotency fields" do
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

    assert {:ok, replay} =
             Runs.record_observation(bootstrap.session, replay_operation, run_result.run, %{
               attrs
               | source_identity: "provider:operation-replay-changed",
                 idempotency_key: "provider-check:operation-replay:changed"
             })

    assert replay.observation.id == first.observation.id
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

  defp create_packet_with_operation(session, idempotency_key, attrs) do
    {:ok, operation} =
      Operations.start_operation(session, :work_packet_create, idempotency_key: idempotency_key)

    WorkPackets.create_packet(session, operation, attrs)
  end

  defp create_ready_run(session, verification_check) when not is_list(verification_check) do
    create_ready_run(session, [verification_check])
  end

  defp create_ready_run(session, verification_checks) when is_list(verification_checks) do
    {:ok, packet_result} = create_ready_packet(session, verification_checks)
    {:ok, run_operation} = Operations.start_operation(session, :work_run_start)

    with {:ok, run_result} <-
           Runs.start_run(session, run_operation, packet_result.version, %{
             source_surface: "test",
             reason: "Execute ready packet.",
             authority_posture: "human_supervised"
           }) do
      {:ok,
       run_result
       |> Map.put(:packet, packet_result.packet)
       |> Map.put(:packet_version, packet_result.version)}
    end
  end

  defp create_ready_packet(session, verification_checks) do
    {:ok, packet_operation} = Operations.start_operation(session, :work_packet_create)

    WorkPackets.create_packet(session, packet_operation, %{
      title: "Ready packet",
      objective: "Run selected work.",
      context_summary: "Ready context.",
      requirements: "Complete selected work.",
      success_criteria: "Required checks pass.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
      verification_check_ids: Enum.map(verification_checks, & &1.id)
    })
  end

  defp record_observation(session, run, verification_check, opts \\ []) do
    key = Keyword.get(opts, :key, Ecto.UUID.generate())
    normalized_status = Keyword.get(opts, :normalized_status, "succeeded")
    observed_status = Keyword.get(opts, :observed_status, "passed")
    freshness_state = Keyword.get(opts, :freshness_state, "fresh")
    trust_basis = Keyword.get(opts, :trust_basis, "owner_attested")

    {:ok, operation} =
      Operations.start_operation(session, :execution_observation_record,
        idempotency_key: "observation-operation:#{key}"
      )

    Runs.record_observation(session, operation, run, %{
      source_kind: "human",
      source_identity: "manual:#{key}",
      idempotency_key: "observation:#{key}",
      observed_status: observed_status,
      normalized_status: normalized_status,
      freshness_state: freshness_state,
      trust_basis: trust_basis,
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Human confirmed #{key}."
    })
  end

  defp create_evidence_candidate(session, run, verification_check, observation, opts) do
    key = Keyword.get(opts, :key, Ecto.UUID.generate())

    {:ok, operation} =
      Operations.start_operation(session, :evidence_candidate_create,
        idempotency_key: "candidate-operation:#{key}"
      )

    Verification.create_evidence_candidate(session, operation, %{
      work_run_id: run.id,
      verification_check_id: verification_check.id,
      execution_observation_id: observation.id,
      claim: "Evidence candidate #{key}.",
      source_kind: "human",
      source_identity: "manual:#{key}",
      freshness_state: Keyword.get(opts, :freshness_state, "fresh"),
      trust_basis: Keyword.get(opts, :trust_basis, "owner_attested"),
      sensitivity: "internal"
    })
  end

  defp accept_candidate(session, candidate, opts) do
    key = Keyword.get(opts, :key, Ecto.UUID.generate())

    {:ok, operation} =
      Operations.start_operation(session, :evidence_accept,
        idempotency_key: "accept-operation:#{key}"
      )

    Verification.accept_evidence_candidate(session, operation, candidate, %{
      title: "Accepted evidence #{key}",
      body: "Accepted evidence body #{key}.",
      result: Keyword.get(opts, :result, "passed"),
      acceptance_policy_basis: "owner_acceptance"
    })
  end

  defp create_required_verification_check(session) do
    with {:ok, graph} <- create_required_verification_graph(session) do
      {:ok, graph.verification_check}
    end
  end

  defp create_required_verification_graph(session) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "Launch signal",
             body: "Launch signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "Launch task",
             body: "Launch task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "Launch finding",
             body: "Launch finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "Launch check",
             body: "Launch check body."
           }) do
      {:ok,
       %{
         signal: signal,
         task: task,
         review_finding: review_finding,
         verification_check: verification_check
       }}
    end
  end

  defp fetch_resource!(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!(authorize?: false)
  end

  defp insert_artifact!(bootstrap, title) do
    artifact_id = Ecto.UUID.generate()

    {:ok, graph_item} =
      Ash.create(
        GraphItem,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          resource_type: "artifact",
          resource_id: artifact_id,
          title: "#{title} graph item"
        },
        action: :create,
        authorize?: false
      )

    Ash.create!(
      Artifact,
      %{
        id: artifact_id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        graph_item_id: graph_item.id,
        title: title,
        uri: "https://example.test/#{artifact_id}"
      },
      action: :create,
      authorize?: false
    )
  end
end
