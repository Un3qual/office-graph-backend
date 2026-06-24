defmodule OfficeGraph.WorkPackets.WorkPacketRunVerificationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

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
  end

  test "observation recording is idempotent for the same source key" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run} = create_ready_run(bootstrap.session, verification_check)

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

    assert {:ok, first} = Runs.record_observation(bootstrap.session, first_operation, run, attrs)

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :execution_observation_record,
        idempotency_key: "provider-check-operation"
      )

    assert {:ok, second} =
             Runs.record_observation(bootstrap.session, second_operation, run, attrs)

    assert second.observation.id == first.observation.id
  end

  defp create_ready_run(session, verification_check) do
    {:ok, packet_operation} = Operations.start_operation(session, :work_packet_create)

    {:ok, packet_result} =
      WorkPackets.create_packet(session, packet_operation, %{
        title: "Ready packet",
        objective: "Run selected work.",
        context_summary: "Ready context.",
        requirements: "Complete selected work.",
        success_criteria: "Required check passes.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: [verification_check.graph_item_id],
        verification_check_ids: [verification_check.id]
      })

    {:ok, run_operation} = Operations.start_operation(session, :work_run_start)

    with {:ok, run_result} <-
           Runs.start_run(session, run_operation, packet_result.version, %{
             source_surface: "test",
             reason: "Execute ready packet.",
             authority_posture: "human_supervised"
           }) do
      {:ok, run_result.run}
    end
  end

  defp create_required_verification_check(session) do
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
      {:ok, verification_check}
    end
  end
end
