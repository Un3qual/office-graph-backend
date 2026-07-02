defmodule OfficeGraph.Projections.OperatorWorkflowTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Authorization.{Capability, Role, RoleAssignment, RoleCapability}
  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.{Principal, Session, SessionContext}
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.Projections
  alias OfficeGraph.QueryCounter
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
    assert row.audit_trace == %{operation_id: nil, resource_count: 0, resources: []}
    assert row.revision_trace == %{operation_id: nil, resource_count: 0, resources: []}
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

  test "operator workflow item links packet-backed runs for applied checks" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "run-linked-triage")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
    {:ok, run_result} = create_ready_run(bootstrap.session, applied.verification_check)

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert work_run_link = Enum.find(detail.graph_links, &(&1.type == "work_run"))
    assert work_run_link.id == run_result.run.id
    assert work_run_link.graph_item_id == nil
    assert work_run_link.state == run_result.run.aggregate_state
  end

  test "operator inbox query count stays bounded across applied rows and graph resources" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    for index <- 1..3 do
      key = "query-scaling-#{index}"
      {:ok, intake} = submit_manual_intake(bootstrap.session, key)
      {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
      {:ok, _run_result} = create_ready_run(bootstrap.session, applied.verification_check)
    end

    {{:ok, inbox}, queries} =
      QueryCounter.count(fn -> Projections.operator_inbox(bootstrap.session) end)

    assert length(inbox.rows) >= 3

    # Accepted budget: each known projection source is read at most once as rows,
    # applied operations, graph resources, packet links, and runs grow.
    assert QueryCounter.source_count(queries, "proposed_graph_changes") <= 1
    assert QueryCounter.source_count(queries, "audit_records") <= 1
    assert QueryCounter.source_count(queries, "revisions") <= 1
    assert QueryCounter.source_count(queries, "signals") <= 1
    assert QueryCounter.source_count(queries, "tasks") <= 1
    assert QueryCounter.source_count(queries, "review_findings") <= 1
    assert QueryCounter.source_count(queries, "verification_checks") <= 1
    assert QueryCounter.source_count(queries, "work_packet_version_required_checks") <= 1
    assert QueryCounter.source_count(queries, "work_packet_version_sources") <= 1
    assert QueryCounter.source_count(queries, "runs") <= 1
  end

  test "trusted session capabilities are revalidated for projection reads" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, _intake} = submit_manual_intake(bootstrap.session, "trusted-auth-query")

    {{:ok, inbox}, queries} =
      QueryCounter.count(fn -> Projections.operator_inbox(bootstrap.session) end)

    assert inbox.empty? == false

    assert QueryCounter.source_count(queries, "role_assignments") >= 1
  end

  test "terminal linked work runs replace packet handoff status" do
    assert_terminal_linked_run_status("verified")
    assert_terminal_linked_run_status("failed")
  end

  test "newer linked work runs replace older failed run status" do
    key = "retry-linked-run-status"
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, key)
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
    {:ok, first_run_result} = create_ready_run(bootstrap.session, applied.verification_check)

    {:ok, accepted} =
      complete_linked_run(
        bootstrap.session,
        first_run_result.run,
        applied.verification_check,
        key,
        "failed"
      )

    assert accepted.work_run.aggregate_state == "failed"

    {:ok, retry_run_result} =
      start_run_for_packet_version(
        bootstrap.session,
        first_run_result.packet_version,
        key <> ":retry"
      )

    assert retry_run_result.run.aggregate_state == "running"

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == "running"
    assert detail.allowed_next_actions == []

    assert [retry_run_link | _older_links] =
             Enum.filter(detail.graph_links, &(&1.type == "work_run"))

    assert retry_run_link.id == retry_run_result.run.id
    assert retry_run_link.state == "running"

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert row = Enum.find(inbox.rows, &(&1.normalized_event_id == intake.normalized_event.id))
    assert row.status == "running"
    assert row.allowed_next_actions == []
  end

  test "directly satisfied checks complete the operator workflow item" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, "directly-satisfied-triage")
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :verification_complete,
        idempotency_key: "directly-satisfied-triage"
      )

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               operation,
               applied.verification_check,
               %{
                 title: "Directly satisfied triage",
                 body: "Direct evidence completed the applied intake item.",
                 artifact_uri: "https://example.test/directly-satisfied-triage"
               }
             )

    assert completed.verification_check.lifecycle_state == "satisfied"

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == "verified"
    assert detail.allowed_next_actions == []

    assert verification_link = Enum.find(detail.graph_links, &(&1.type == "verification_check"))
    assert verification_link.id == applied.verification_check.id
    assert verification_link.state == "satisfied"

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert row = Enum.find(inbox.rows, &(&1.normalized_event_id == intake.normalized_event.id))
    assert row.status == "verified"
    assert row.allowed_next_actions == []
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

    missing_title_attrs = Map.delete(ready_attrs, :title)

    assert {:ok, missing_title} =
             Projections.packet_readiness(bootstrap.session, missing_title_attrs)

    assert missing_title.ready? == false
    assert missing_title.status == "blocked"
    assert missing_title.allowed_next_actions == []
    assert missing_title.blocker_reasons == ["missing_title"]

    assert {:ok, blank_title} =
             Projections.packet_readiness(bootstrap.session, %{ready_attrs | title: " "})

    assert blank_title.ready? == false
    assert blank_title.status == "blocked"
    assert blank_title.allowed_next_actions == []
    assert blank_title.blocker_reasons == ["missing_title"]

    read_only_session = create_read_only_session!(bootstrap)

    assert {:ok, unauthorized} = Projections.packet_readiness(read_only_session, ready_attrs)
    assert unauthorized.ready? == false
    assert unauthorized.status == "blocked"
    assert unauthorized.allowed_next_actions == []
    assert unauthorized.blocker_reasons == ["missing_work_packet_create_capability"]

    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)

    mismatched_attrs = %{ready_attrs | verification_check_ids: [unrelated_check.id]}

    assert {:ok, mismatched} = Projections.packet_readiness(bootstrap.session, mismatched_attrs)
    assert mismatched.ready? == false
    assert mismatched.status == "blocked"
    assert mismatched.allowed_next_actions == []
    assert mismatched.blocker_reasons == ["source_graph_item_check_mismatch"]

    duplicate_check_attrs = %{
      ready_attrs
      | verification_check_ids: [verification_check.id, verification_check.id]
    }

    assert {:ok, duplicate_check} =
             Projections.packet_readiness(bootstrap.session, duplicate_check_attrs)

    assert duplicate_check.ready? == false
    assert duplicate_check.status == "blocked"
    assert duplicate_check.allowed_next_actions == []
    assert duplicate_check.blocker_reasons == ["duplicate_verification_check_ids"]

    duplicate_source_attrs = %{
      ready_attrs
      | source_graph_item_ids: [
          verification_check.graph_item_id,
          verification_check.graph_item_id
        ]
    }

    assert {:ok, duplicate_source} =
             Projections.packet_readiness(bootstrap.session, duplicate_source_attrs)

    assert duplicate_source.ready? == false
    assert duplicate_source.status == "blocked"
    assert duplicate_source.allowed_next_actions == []
    assert duplicate_source.blocker_reasons == ["duplicate_source_graph_item_ids"]

    {:ok, completion_operation} =
      Operations.start_operation(bootstrap.session, :verification_complete,
        idempotency_key: "packet-readiness-satisfied-check"
      )

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               completion_operation,
               verification_check,
               %{
                 title: "Satisfied before readiness",
                 body: "Direct completion satisfies the check before packet readiness.",
                 artifact_uri: "https://example.test/packet-readiness-satisfied-check"
               }
             )

    assert completed.verification_check.lifecycle_state == "satisfied"

    assert {:ok, satisfied_check} = Projections.packet_readiness(bootstrap.session, ready_attrs)
    assert satisfied_check.ready? == false
    assert satisfied_check.status == "blocked"
    assert satisfied_check.allowed_next_actions == []
    assert satisfied_check.blocker_reasons == ["non_required_verification_check"]

    not_ready_attrs =
      Map.merge(ready_attrs, %{
        objective: "",
        context_summary: "",
        requirements: "",
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
             "missing_context_summary",
             "missing_requirements",
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
             %{verification_check_id: verification_check.id, reason: "missing_accepted_evidence"}
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

    assert [
             %{
               id: candidate_id,
               state: "candidate",
               freshness_state: "fresh",
               trust_basis: "owner_attested",
               execution_observation_id: observation_id
             }
           ] = awaiting_evidence.evidence_candidates

    assert candidate_id == candidate.id
    assert observation_id == observation_result.observation.id

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate, key: "operator-run-state", result: "passed")

    assert {:ok, verified_state} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    assert verified_state.status == "verified"
    assert verified_state.allowed_next_actions == []
    assert verified_state.missing_evidence == []
    assert [%{id: evidence_item_id, state: "accepted"}] = verified_state.evidence_items
    assert evidence_item_id == accepted.evidence_item.id

    assert [
             %{
               id: result_id,
               result: "passed",
               evidence_item_id: evidence_item_id,
               operation_id: operation_id,
               actor_principal_id: actor_principal_id,
               policy_basis: "owner_acceptance",
               target_graph_item_id: target_graph_item_id
             }
           ] = verified_state.verification_results

    assert result_id == accepted.verification_result.id
    assert evidence_item_id == accepted.evidence_item.id
    assert operation_id == accepted.verification_result.operation_id
    assert actor_principal_id == bootstrap.session.principal_id
    assert target_graph_item_id == verification_check.graph_item_id
  end

  test "operator run state does not offer acceptance for unusable evidence candidates" do
    for {key, overrides} <- [
          {"stale-candidate", [freshness_state: "stale"]},
          {"untrusted-candidate", [trust_basis: "unauthenticated"]}
        ] do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      {:ok, verification_check} = create_required_verification_check(bootstrap.session)
      {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

      {:ok, observation_result} =
        record_observation(bootstrap.session, run_result.run, verification_check,
          key: "operator-run-state-#{key}"
        )

      {:ok, candidate} =
        create_evidence_candidate(
          bootstrap.session,
          run_result.run,
          verification_check,
          observation_result.observation,
          Keyword.put(overrides, :key, "operator-run-state-#{key}")
        )

      assert {:ok, awaiting_evidence} =
               Projections.operator_run_state(bootstrap.session, run_result.run.id)

      assert awaiting_evidence.status == "awaiting_evidence"
      assert awaiting_evidence.allowed_next_actions == ["create_evidence_candidate"]

      assert Enum.any?(
               awaiting_evidence.evidence_candidates,
               &(&1.id == candidate.id and &1.state == "candidate")
             )
    end
  end

  test "operator run state keeps acceptance action for pending candidates on missing checks" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, [first_check, second_check])

    {:ok, first_observation} =
      record_observation(bootstrap.session, run_result.run, first_check,
        key: "partial-multi-check-first"
      )

    {:ok, first_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        first_check,
        first_observation.observation,
        key: "partial-multi-check-first"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, first_candidate,
        key: "partial-multi-check-first",
        result: "passed"
      )

    {:ok, second_observation} =
      record_observation(bootstrap.session, accepted.work_run, second_check,
        key: "partial-multi-check-second"
      )

    {:ok, second_candidate} =
      create_evidence_candidate(
        bootstrap.session,
        second_observation.run,
        second_check,
        second_observation.observation,
        key: "partial-multi-check-second"
      )

    assert {:ok, waiting_state} =
             Projections.operator_run_state(bootstrap.session, second_observation.run.id)

    assert waiting_state.status == "awaiting_evidence_acceptance"
    assert waiting_state.allowed_next_actions == ["accept_evidence"]

    assert Enum.any?(
             waiting_state.evidence_candidates,
             &(&1.id == second_candidate.id and &1.verification_check_id == second_check.id and
                 &1.state == "candidate")
           )

    assert waiting_state.missing_evidence == [
             %{verification_check_id: second_check.id, reason: "missing_accepted_evidence"}
           ]
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
             %{verification_check_id: verification_check.id, reason: "missing_accepted_evidence"}
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

  defp create_ready_run(session, verification_check) when not is_list(verification_check) do
    create_ready_run(session, [verification_check])
  end

  defp create_ready_run(session, verification_checks) when is_list(verification_checks) do
    {:ok, packet_operation} = Operations.start_operation(session, :work_packet_create)

    {:ok, packet_result} =
      WorkPackets.create_packet(session, packet_operation, %{
        title: "Ready operator packet",
        objective: "Run selected work.",
        context_summary: "Ready context.",
        requirements: "Complete selected work.",
        success_criteria: "Required checks pass.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
        verification_check_ids: Enum.map(verification_checks, & &1.id)
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

  defp create_read_only_session!(bootstrap) do
    suffix = System.unique_integer([:positive])
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    role_id = Ecto.UUID.generate()

    principal =
      Ash.create!(
        Principal,
        %{
          id: principal_id,
          email: "operator-read-only-#{suffix}@office-graph.local",
          kind: "human",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    session =
      Ash.create!(
        Session,
        %{
          id: session_id,
          principal_id: principal.id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          purpose: "operator_read_only_#{suffix}"
        },
        action: :create,
        authorize?: false
      )

    capability = Ash.get!(Capability, %{key: "skeleton.read"}, authorize?: false)

    role =
      Ash.create!(
        Role,
        %{
          id: role_id,
          organization_id: bootstrap.organization.id,
          key: "operator_read_only_#{suffix}",
          name: "Operator Read Only #{suffix}"
        },
        action: :create,
        authorize?: false
      )

    Ash.create!(
      RoleCapability,
      %{
        id: Ecto.UUID.generate(),
        role_id: role.id,
        capability_id: capability.id
      },
      action: :create,
      authorize?: false
    )

    Ash.create!(
      RoleAssignment,
      %{
        id: Ecto.UUID.generate(),
        principal_id: principal.id,
        role_id: role.id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id
      },
      action: :create,
      authorize?: false
    )

    %SessionContext{
      principal_id: principal.id,
      session_id: session.id,
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      capabilities: MapSet.new(["skeleton.read"])
    }
  end

  defp start_run_for_packet_version(session, packet_version, key) do
    {:ok, run_operation} =
      Operations.start_operation(session, :work_run_start,
        idempotency_key: "work-run-operation:#{key}"
      )

    Runs.start_run(session, run_operation, packet_version, %{
      source_surface: "test",
      reason: "Retry ready packet.",
      authority_posture: "human_supervised"
    })
  end

  defp assert_terminal_linked_run_status(expected_status) do
    key = "terminal-linked-run-#{expected_status}"
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake} = submit_manual_intake(bootstrap.session, key)
    {:ok, applied} = apply_changes(bootstrap.session, intake.proposed_changes)
    {:ok, run_result} = create_ready_run(bootstrap.session, applied.verification_check)

    {:ok, accepted} =
      complete_linked_run(
        bootstrap.session,
        run_result.run,
        applied.verification_check,
        key,
        expected_status
      )

    assert {:ok, detail} =
             Projections.operator_workflow_item(bootstrap.session, intake.normalized_event.id)

    assert detail.status == expected_status
    assert detail.allowed_next_actions == []

    assert work_run_link = Enum.find(detail.graph_links, &(&1.type == "work_run"))
    assert work_run_link.id == accepted.work_run.id
    assert work_run_link.state == expected_status

    assert {:ok, inbox} = Projections.operator_inbox(bootstrap.session)
    assert row = Enum.find(inbox.rows, &(&1.normalized_event_id == intake.normalized_event.id))
    assert row.status == expected_status
    assert row.allowed_next_actions == []
  end

  defp complete_linked_run(session, run, verification_check, key, "verified") do
    {:ok, observation_result} = record_observation(session, run, verification_check, key: key)

    {:ok, candidate} =
      create_evidence_candidate(session, run, verification_check, observation_result.observation,
        key: key
      )

    accept_candidate(session, candidate, key: key, result: "passed")
  end

  defp complete_linked_run(session, run, verification_check, key, "failed") do
    {:ok, observation_result} =
      record_observation(session, run, verification_check,
        key: key,
        observed_status: "failed",
        normalized_status: "failed"
      )

    {:ok, candidate} =
      create_evidence_candidate(session, run, verification_check, observation_result.observation,
        key: key
      )

    accept_candidate(session, candidate, key: key, result: "failed")
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
    freshness_state = Keyword.get(opts, :freshness_state, "fresh")
    trust_basis = Keyword.get(opts, :trust_basis, "owner_attested")

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
      freshness_state: freshness_state,
      trust_basis: trust_basis,
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
