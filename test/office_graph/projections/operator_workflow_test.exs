defmodule OfficeGraph.Projections.OperatorWorkflowTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.Projections
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  test "operator inbox exposes pending manual intake as actionable triage" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "pending-triage")

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert inbox.empty? == false
    assert inbox.source_watermark == intake.normalized_event.operation_id

    assert [row] = inbox.rows
    assert row.typed_id == %{type: "normalized_intake_event", id: intake.normalized_event.id}
    assert row.status == "pending_triage"
    assert row.reason_codes == []
    assert row.blocker_reasons == []
    assert row.allowed_next_actions == ["apply_proposed_changes"]
    assert row.operation_watermark == intake.normalized_event.operation_id

    assert row.source == %{
             identity: "manual:pending-triage",
             replay_identity: "paste:pending-triage",
             outcome: "accepted"
           }

    assert row.proposed_change_status == %{
             pending: 4,
             applied: 0,
             rejected: 0,
             total: 4
           }

    assert row.graph_links == []
  end

  test "operator workflow item exposes applied graph links and traces" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "applied-triage")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == "ready_for_packet"
    assert detail.allowed_next_actions == ["prepare_packet"]
    assert detail.blocker_reasons == []

    graph_link_types = Enum.map(detail.graph_links, & &1.type)
    assert graph_link_types == ["signal", "task", "review_finding", "verification_check"]

    assert Enum.find(detail.graph_links, &(&1.type == "signal")).id == applied.signal.id
    assert Enum.find(detail.graph_links, &(&1.type == "task")).id == applied.task.id

    assert Enum.find(detail.graph_links, &(&1.type == "review_finding")).id ==
             applied.review_finding.id

    assert Enum.find(detail.graph_links, &(&1.type == "verification_check")).id ==
             applied.verification_check.id

    assert Enum.map(detail.graph_relationships, & &1.relationship_type) == [
             "produced_task",
             "has_review_finding",
             "requires_verification"
           ]

    assert detail.audit_trace.resource_count == 4
    assert detail.revision_trace.resource_count == 4
  end

  test "operator inbox presents duplicate intake as not actionable" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, accepted} = submit_manual_intake(bootstrap.session, "duplicate-intake")
    {:ok, duplicate} = submit_manual_intake(bootstrap.session, "duplicate-intake")

    assert duplicate.normalized_event.outcome == "duplicate"

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert [duplicate_row, accepted_row] = inbox.rows

    assert duplicate_row.typed_id == %{
             type: "normalized_intake_event",
             id: duplicate.normalized_event.id
           }

    assert duplicate_row.status == "not_actionable"
    assert duplicate_row.reason_codes == ["duplicate_intake"]
    assert duplicate_row.allowed_next_actions == ["view_existing_intake"]
    assert duplicate_row.blocker_reasons == ["duplicate_intake"]
    assert duplicate_row.duplicate_of_id == accepted.normalized_event.id

    assert accepted_row.typed_id == %{
             type: "normalized_intake_event",
             id: accepted.normalized_event.id
           }
  end

  test "packet readiness reports ready inputs and blocking reasons" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    ready_attrs = %{
      title: "Ready operator packet",
      objective: "Resolve the selected verification check.",
      context_summary: "A triaged item is ready for operator execution.",
      requirements: "Use the linked task and finding as execution context.",
      success_criteria: "The required verification check has accepted passing evidence.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [verification_check.graph_item_id],
      verification_check_ids: [verification_check.id]
    }

    assert {:ok, ready} = Projections.packet_readiness(bootstrap.session, ready_attrs)
    assert ready.ready? == true
    assert ready.status == "packet_ready"
    assert ready.blocker_reasons == []
    assert ready.allowed_next_actions == ["create_work_packet"]

    assert ready.required_checks == [
             %{
               id: verification_check.id,
               graph_item_id: verification_check.graph_item_id,
               state: "required"
             }
           ]

    not_ready_attrs =
      Map.merge(ready_attrs, %{
        objective: "",
        success_criteria: "",
        autonomy_posture: "fully_autonomous",
        source_graph_item_ids: [],
        verification_check_ids: []
      })

    assert {:ok, not_ready} = Projections.packet_readiness(bootstrap.session, not_ready_attrs)
    assert not_ready.ready? == false
    assert not_ready.status == "blocked"
    assert not_ready.allowed_next_actions == []

    assert not_ready.blocker_reasons == [
             "missing_objective",
             "missing_success_criteria",
             "missing_source_graph_items",
             "missing_verification_checks",
             "unsupported_autonomy_posture"
           ]
  end

  test "operator run state moves from missing evidence to verified" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    assert {:ok, initial_state} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert initial_state.status == "awaiting_execution"
    assert initial_state.allowed_next_actions == ["record_observation"]

    assert initial_state.missing_evidence == [
             %{verification_check_id: verification_check.id, reason: "missing_evidence"}
           ]

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "operator-run-state"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "operator-run-state"
      )

    assert {:ok, awaiting_evidence} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert awaiting_evidence.status == "awaiting_evidence_acceptance"
    assert awaiting_evidence.allowed_next_actions == ["accept_evidence"]
    assert [%{id: candidate_id, state: "candidate"}] = awaiting_evidence.evidence_candidates
    assert candidate_id == candidate.id

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate, key: "operator-run-state", result: "passed")

    assert {:ok, verified_state} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    assert verified_state.status == "verified"
    assert verified_state.allowed_next_actions == []
    assert verified_state.missing_evidence == []
    assert [%{id: evidence_item_id, state: "accepted"}] = verified_state.evidence_items
    assert evidence_item_id == accepted.evidence_item.id
    assert [%{id: result_id, result: "passed"}] = verified_state.verification_results
    assert result_id == accepted.verification_result.id
  end

  test "operator run state exposes failed evidence without completing the workflow" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "operator-failed-run-state",
        observed_status: "failed",
        normalized_status: "failed"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "operator-failed-run-state"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate,
        key: "operator-failed-run-state",
        result: "failed"
      )

    assert {:ok, failed_state} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    assert failed_state.status == "failed"
    assert failed_state.allowed_next_actions == []

    assert failed_state.missing_evidence == [
             %{verification_check_id: verification_check.id, reason: "missing_evidence"}
           ]

    assert [%{id: result_id, result: "failed"}] = failed_state.verification_results
    assert result_id == accepted.verification_result.id
  end

  defp submit_manual_intake(session, key) do
    {:ok, operation} =
      Operations.start_operation(session, :manual_intake_submit,
        idempotency_key: "manual-intake:#{key}:#{System.unique_integer([:positive])}"
      )

    Integrations.submit_manual_intake(session, operation, %{
      source_identity: "manual:#{key}",
      replay_identity: "paste:#{key}",
      body: "Investigate #{key} and prove the result with accepted evidence."
    })
  end

  defp apply_changes(session, proposed_changes) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)
    ProposedChanges.apply_all(session, operation, proposed_changes)
  end

  defp create_required_verification_check(session) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "Operator signal",
             body: "Operator signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "Operator task",
             body: "Operator task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "Operator finding",
             body: "Operator finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "Operator check",
             body: "Operator check body."
           }) do
      {:ok, verification_check}
    end
  end

  defp create_ready_run(session, verification_check) do
    {:ok, packet_operation} = Operations.start_operation(session, :work_packet_create)

    {:ok, packet_result} =
      WorkPackets.create_packet(session, packet_operation, %{
        title: "Ready operator packet",
        objective: "Run selected work.",
        context_summary: "Ready context.",
        requirements: "Complete selected work.",
        success_criteria: "Required checks pass.",
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
      {:ok, Map.put(run_result, :packet_version, packet_result.version)}
    end
  end

  defp record_observation(session, run, verification_check, opts) do
    key = Keyword.fetch!(opts, :key)
    observed_status = Keyword.get(opts, :observed_status, "passed")
    normalized_status = Keyword.get(opts, :normalized_status, "succeeded")

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
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Human confirmed #{key}."
    })
  end

  defp create_evidence_candidate(session, run, verification_check, observation, opts) do
    key = Keyword.fetch!(opts, :key)

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
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      sensitivity: "internal"
    })
  end

  defp accept_candidate(session, candidate, opts) do
    key = Keyword.fetch!(opts, :key)

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
end
