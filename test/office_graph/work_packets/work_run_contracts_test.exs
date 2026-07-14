defmodule OfficeGraph.WorkPackets.WorkRunContractsTest do
  use OfficeGraph.TestSupport.WorkPacketCommandLoopSupport

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

    assert "satisfied" ==
             fetch_resource!(WorkGraph.VerificationCheck, verification_check.id).lifecycle_state
  end

  test "accepted evidence candidates link evidence and artifact graph items" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)
    artifact = insert_artifact!(bootstrap, "Candidate artifact")

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "candidate-evidence-relationships"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "candidate-evidence-relationships",
        artifact_id: artifact.id
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate,
        key: "candidate-evidence-relationships",
        result: "passed"
      )

    assert relationship_exists?(
             verification_check.graph_item_id,
             accepted.evidence_item.graph_item_id,
             "evidenced_by"
           )

    assert relationship_exists?(
             accepted.evidence_item.graph_item_id,
             artifact.graph_item_id,
             "generated_from"
           )
  end

  test "accepted evidence candidates record audit and revision trace rows" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "candidate-evidence-traces"
      )

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "candidate-evidence-traces"
      )

    {:ok, acceptance_operation} =
      Operations.start_operation(bootstrap.session, :evidence_accept,
        idempotency_key: "candidate-evidence-traces-accept"
      )

    assert {:ok, accepted} =
             Verification.accept_evidence_candidate(
               bootstrap.session,
               acceptance_operation,
               candidate,
               %{
                 title: "Candidate evidence traces",
                 body: "Candidate acceptance should emit trace rows.",
                 result: "passed",
                 acceptance_policy_basis: "owner_acceptance"
               }
             )

    assert accepted.evidence_item.candidate_id == candidate.id
    assert Audit.count_for_operation(acceptance_operation.id) >= 2
    assert Revisions.count_for_operation(acceptance_operation.id) >= 2
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

    assert {:error, error} =
             Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
               source_surface: "test",
               reason: "Should be rejected.",
               authority_posture: "human_supervised"
             })

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"

    stale_version = %{packet_result.version | lifecycle_state: "stale"}
    superseded_version = %{packet_result.version | lifecycle_state: "superseded"}

    assert {:error, error} =
             Runs.start_run(bootstrap.session, run_operation, stale_version, %{
               source_surface: "test",
               reason: "Stale versions cannot start runs.",
               authority_posture: "human_supervised"
             })

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"

    assert {:error, error} =
             Runs.start_run(bootstrap.session, run_operation, superseded_version, %{
               source_surface: "test",
               reason: "Superseded versions cannot start runs.",
               authority_posture: "human_supervised"
             })

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"

    assert {:error, :missing_packet_version} ==
             Runs.start_run(bootstrap.session, run_operation, nil, %{
               source_surface: "test",
               reason: "Missing versions cannot start runs.",
               authority_posture: "human_supervised"
             })
  end

  test "work run start rejects a ready version that is no longer current" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    version_attrs = %{
      expected_current_version_id: packet_result.version.id,
      title: "Current ready packet",
      objective: "Run only the current selected work.",
      context_summary: "Current ready context.",
      requirements: "Reject superseded packet versions.",
      success_criteria: "The current required check passes.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [verification_check.graph_item_id],
      verification_check_ids: [verification_check.id]
    }

    {:ok, version_operation} =
      Operations.start_command(
        bootstrap.session,
        :work_packet_version_create,
        "supersede-ready-run-version",
        Map.put(version_attrs, :packet_id, packet_result.packet.id)
      )

    assert {:ok, revised} =
             WorkPackets.create_version(
               bootstrap.session,
               version_operation,
               packet_result.packet,
               version_attrs
             )

    assert revised.version.lifecycle_state == "ready"

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "reject-superseded-ready-run-version"
      )

    assert {:error, {:stale_packet_version, packet_id, current_version_id}} =
             Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
               source_surface: "test",
               reason: "A superseded ready version must not start.",
               authority_posture: "human_supervised"
             })

    assert packet_id == packet_result.packet.id
    assert current_version_id == revised.version.id
  end

  test "work run start rejects a second active run for the current packet version" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    {:ok, first_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "active-run-first"
      )

    attrs = %{
      source_surface: "test",
      reason: "Only one active run may execute this packet version.",
      authority_posture: "human_supervised"
    }

    assert {:ok, first_result} =
             Runs.start_run(bootstrap.session, first_operation, packet_result.version, attrs)

    {:ok, second_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "active-run-second"
      )

    assert {:error, {:active_work_run, packet_version_id, active_run_id}} =
             Runs.start_run(bootstrap.session, second_operation, packet_result.version, attrs)

    assert packet_version_id == packet_result.version.id
    assert active_run_id == first_result.run.id
  end

  test "work run start rejects packet versions whose checks are already satisfied" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    {:ok, completion_operation} =
      Operations.start_operation(bootstrap.session, :verification_complete,
        idempotency_key: "stale-packet-direct-completion"
      )

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               completion_operation,
               verification_check,
               %{
                 title: "Direct stale packet evidence",
                 body: "Direct completion satisfies the check before run start.",
                 artifact_uri: "https://example.test/stale-packet-direct-completion"
               }
             )

    assert completed.verification_check.lifecycle_state == "satisfied"

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "stale-packet-direct-completion-run"
      )

    assert {:error, error} =
             Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
               source_surface: "test",
               reason: "Stale packet versions cannot start runs.",
               authority_posture: "human_supervised"
             })

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"
  end

  test "work packet operation replay rejects changed packet input" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-create-operation-input-conflict"
      )

    attrs = %{
      title: "Replay guarded packet",
      objective: "Create a packet once.",
      context_summary: "Packet replay conflict context.",
      requirements: "Keep operation replays stable.",
      success_criteria: "The original packet facts are preserved.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [first_check.graph_item_id],
      verification_check_ids: [first_check.id]
    }

    assert {:ok, packet_result} = WorkPackets.create_packet(bootstrap.session, operation, attrs)

    {:ok, replay_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-create-operation-input-conflict"
      )

    packet_id = packet_result.packet.id

    assert {:error, {:work_packet_operation_conflict, ^packet_id}} =
             WorkPackets.create_packet(bootstrap.session, replay_operation, %{
               attrs
               | source_graph_item_ids: [second_check.graph_item_id],
                 verification_check_ids: [second_check.id]
             })
  end

  test "work packet operation replay rejects reordered packet child input" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    verification_checks =
      Enum.map(1..2, fn _index ->
        {:ok, verification_check} = create_required_verification_check(bootstrap.session)
        verification_check
      end)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-create-operation-order-conflict"
      )

    attrs = %{
      title: "Replay order guarded packet",
      objective: "Create an ordered packet once.",
      context_summary: "Packet replay order conflict context.",
      requirements: "Keep ordered operation replays stable.",
      success_criteria: "The original packet order is preserved.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
      verification_check_ids: Enum.map(verification_checks, & &1.id)
    }

    assert {:ok, packet_result} = WorkPackets.create_packet(bootstrap.session, operation, attrs)

    {:ok, replay_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-create-operation-order-conflict"
      )

    packet_id = packet_result.packet.id

    assert {:error, {:work_packet_operation_conflict, ^packet_id}} =
             WorkPackets.create_packet(bootstrap.session, replay_operation, %{
               attrs
               | source_graph_item_ids: Enum.reverse(attrs.source_graph_item_ids)
             })

    assert {:error, {:work_packet_operation_conflict, ^packet_id}} =
             WorkPackets.create_packet(bootstrap.session, replay_operation, %{
               attrs
               | verification_check_ids: Enum.reverse(attrs.verification_check_ids)
             })
  end

  test "work packet operation replay returns existing packet after checks are satisfied" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-create-replay-after-satisfied"
      )

    attrs = %{
      title: "Replay after satisfied check",
      objective: "Create a packet before direct verification.",
      context_summary: "Replay should return the existing packet facts.",
      requirements: "Do not revalidate current check state on operation replay.",
      success_criteria: "The original packet is returned.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [verification_check.graph_item_id],
      verification_check_ids: [verification_check.id]
    }

    assert {:ok, packet_result} = WorkPackets.create_packet(bootstrap.session, operation, attrs)

    {:ok, completion_operation} =
      Operations.start_operation(bootstrap.session, :verification_complete,
        idempotency_key: "packet-create-replay-after-satisfied-completion"
      )

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               completion_operation,
               verification_check,
               %{
                 title: "Satisfied before packet replay",
                 body: "The check is satisfied after the original packet commit.",
                 artifact_uri: "https://example.test/packet-create-replay-after-satisfied"
               }
             )

    assert completed.verification_check.lifecycle_state == "satisfied"

    {:ok, replay_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-create-replay-after-satisfied"
      )

    assert {:ok, replay_result} =
             WorkPackets.create_packet(bootstrap.session, replay_operation, attrs)

    assert replay_result.packet.id == packet_result.packet.id
    assert replay_result.version.id == packet_result.version.id
  end

  test "work packet replay validates current version ownership" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-current-version-mismatch"
      )

    attrs = %{
      title: "Current version guarded packet",
      objective: "Create the guarded packet.",
      context_summary: "Current-version replay context.",
      requirements: "Replay must load this packet version.",
      success_criteria: "The current version belongs to the packet.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [first_check.graph_item_id],
      verification_check_ids: [first_check.id]
    }

    assert {:ok, packet_result} = WorkPackets.create_packet(bootstrap.session, operation, attrs)
    {:ok, other_packet} = create_ready_packet(bootstrap.session, [second_check])

    forge_packet_current_version!(packet_result.packet.id, other_packet.version.id)

    {:ok, replay_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "packet-current-version-mismatch"
      )

    packet_id = packet_result.packet.id
    other_version_id = other_packet.version.id

    assert {:error, {:packet_current_version_mismatch, ^packet_id, ^other_version_id}} =
             WorkPackets.create_packet(bootstrap.session, replay_operation, attrs)
  end

  test "direct packet creates derive draft state" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "direct-packet-create-derived-state"
      )

    assert {:ok, packet} =
             Ash.create(
               WorkPacket,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: operation.id,
                 title: "Direct packet create derives state"
               },
               action: :create,
               authorize?: false
             )

    assert packet.state == "draft"
  end

  test "direct packet version creates derive readiness and packet updates sync selected version state" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "direct-version-readiness-packet"
      )

    {:ok, packet} =
      Ash.create(
        WorkPacket,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: packet_operation.id,
          title: "Direct readiness packet"
        },
        action: :create,
        authorize?: false
      )

    {:ok, version_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "direct-version-readiness-version"
      )

    {:ok, version} =
      Ash.create(
        WorkPacketVersion,
        %{
          id: Ecto.UUID.generate(),
          work_packet_id: packet.id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: version_operation.id,
          version_number: 1,
          title: "Ready version",
          objective: "Create a ready version.",
          context_summary: "Readiness derives from version facts.",
          requirements: "Use packet contract inputs.",
          success_criteria: "Source and check references are present.",
          autonomy_posture: "human_supervised",
          source_graph_item_ids: [verification_check.graph_item_id],
          verification_check_ids: [verification_check.id]
        },
        action: :create,
        authorize?: false
      )

    assert version.lifecycle_state == "ready"

    {:ok, updated_packet} =
      packet
      |> Ash.Changeset.for_update(:set_current_version, %{current_version_id: version.id})
      |> Ash.update(authorize?: false)

    assert updated_packet.current_version_id == version.id
    assert updated_packet.state == "ready"
  end

  test "direct packet version creates derive draft state from missing readiness inputs" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "direct-draft-version-packet"
      )

    {:ok, packet} =
      Ash.create(
        WorkPacket,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: packet_operation.id,
          title: "Direct draft packet"
        },
        action: :create,
        authorize?: false
      )

    {:ok, version_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "direct-draft-version"
      )

    assert {:ok, version} =
             Ash.create(
               WorkPacketVersion,
               %{
                 id: Ecto.UUID.generate(),
                 work_packet_id: packet.id,
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: version_operation.id,
                 version_number: 1,
                 title: "Draft version",
                 objective: "Create a draft version.",
                 context_summary: "Draft derives from missing readiness inputs.",
                 requirements: "Do not let callers force readiness.",
                 success_criteria: nil,
                 autonomy_posture: "human_supervised"
               },
               action: :create,
               authorize?: false
             )

    assert version.lifecycle_state == "draft"

    refute WorkPackets.Readiness.ready?(%{
             objective: "Create a context-blocked version.",
             context_summary: "",
             requirements: "",
             success_criteria: "Accepted evidence exists.",
             autonomy_posture: "human_supervised",
             source_graph_item_ids: [Ecto.UUID.generate()],
             verification_check_ids: [Ecto.UUID.generate()]
           })

    assert {:error, error} =
             Ash.create(
               WorkPacketVersion,
               %{
                 id: Ecto.UUID.generate(),
                 work_packet_id: packet.id,
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 operation_id: version_operation.id,
                 version_number: 2,
                 title: "Forced-ready version",
                 objective: "Create a forced-ready version.",
                 context_summary: "Callers cannot force readiness.",
                 requirements: "Reject lifecycle input.",
                 success_criteria: nil,
                 autonomy_posture: "human_supervised",
                 lifecycle_state: "ready"
               },
               action: :create,
               authorize?: false
             )

    assert Exception.message(error) =~ "No such input `lifecycle_state`"
  end

  test "direct packet current-version updates reject versions from another packet" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, first_packet} = create_ready_packet(bootstrap.session, [first_check])
    {:ok, second_packet} = create_ready_packet(bootstrap.session, [second_check])

    assert {:error, error} =
             first_packet.packet
             |> Ash.Changeset.for_update(:set_current_version, %{
               current_version_id: second_packet.version.id
             })
             |> Ash.update(authorize?: false)

    assert Exception.message(error) =~ "current_version_id"
  end

  test "work run start operation replay rejects changed run input" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, first_packet} = create_ready_packet(bootstrap.session, [first_check])
    {:ok, second_packet} = create_ready_packet(bootstrap.session, [second_check])

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "work-run-operation-input-conflict"
      )

    attrs = %{
      source_surface: "test",
      reason: "Start the selected packet once.",
      authority_posture: "human_supervised"
    }

    assert {:ok, run_result} =
             Runs.start_run(bootstrap.session, operation, first_packet.version, attrs)

    {:ok, replay_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "work-run-operation-input-conflict"
      )

    run_id = run_result.run.id

    assert {:error, {:work_run_operation_conflict, ^run_id}} =
             Runs.start_run(bootstrap.session, replay_operation, second_packet.version, %{
               attrs
               | reason: "Changed packet target."
             })
  end

  test "work run start rejects authority outside the packet autonomy envelope" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "work-run-authority-envelope"
      )

    assert {:error, error} =
             Runs.start_run(bootstrap.session, operation, packet_result.version, %{
               source_surface: "test",
               reason: "Reject escalated authority.",
               authority_posture: "fully_autonomous"
             })

    assert Exception.message(error) =~ "authority_posture must match the packet autonomy posture"

    refute run_for_operation?(operation.id)
  end

  test "work run start rejects malformed ready packet versions without execution links" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "malformed-ready-packet-version"
      )

    packet_id = Ecto.UUID.generate()
    version_id = Ecto.UUID.generate()

    {:ok, packet} =
      Ash.create(
        WorkPacket,
        %{
          id: packet_id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: packet_operation.id,
          title: "Malformed ready packet"
        },
        action: :create,
        authorize?: false
      )

    {:ok, version} =
      Ash.create(
        WorkPacketVersion,
        %{
          id: version_id,
          work_packet_id: packet.id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: packet_operation.id,
          version_number: 1,
          title: "Malformed packet version",
          objective: "Malformed ready packet version.",
          context_summary: "Missing source and required-check rows.",
          requirements: "Should not be executable.",
          success_criteria: "All required checks pass.",
          autonomy_posture: "human_supervised",
          source_graph_item_ids: [verification_check.graph_item_id],
          verification_check_ids: [verification_check.id]
        },
        action: :create,
        authorize?: false
      )

    {:ok, packet} =
      packet
      |> Ash.Changeset.for_update(:set_current_version, %{
        current_version_id: version_id
      })
      |> Ash.update(authorize?: false)

    assert packet.current_version_id == version_id

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "malformed-ready-packet-version-run"
      )

    assert {:error, error} =
             Runs.start_run(bootstrap.session, run_operation, version, %{
               source_surface: "test",
               reason: "Malformed ready versions cannot start runs.",
               authority_posture: "human_supervised"
             })

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"

    refute run_exists_for_operation?(run_operation.id)
  end

  test "work run start rejects persisted ready packet versions missing execution context" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    blank_packet_execution_context!(packet_result.version.id)

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "legacy-ready-packet-without-context-run"
      )

    assert {:error, error} =
             Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
               source_surface: "test",
               reason: "Persisted ready versions still need context.",
               authority_posture: "human_supervised"
             })

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"

    refute run_exists_for_operation?(run_operation.id)
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
    {:ok, unrelated_check} = create_required_verification_check(first_scope.session)
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

    assert {:error, %Ash.Error.Invalid{}} =
             create_packet_with_operation(first_scope.session, "mismatched-source-check", %{
               title: "Mismatched source and check",
               objective: "Reject unrelated source/check pairs.",
               context_summary: "Same-scope references still need to describe the same work.",
               requirements: "Use checks tied to the selected source graph.",
               success_criteria: "Validation returns an error.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [verification_check.graph_item_id],
               verification_check_ids: [unrelated_check.id]
             })
  end

  test "work packet creation rejects duplicate verification check ids before inserting joins" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    assert {:error, error} =
             create_packet_with_operation(bootstrap.session, "duplicate-required-check", %{
               title: "Duplicate check packet",
               objective: "Reject duplicate checks.",
               context_summary: "Packet required checks must be unique.",
               requirements: "Use each verification check once.",
               success_criteria: "Validation returns an error before join inserts.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [verification_check.graph_item_id],
               verification_check_ids: [verification_check.id, verification_check.id]
             })

    assert Exception.message(error) =~ "verification_check_ids must not include duplicate ids"
  end

  test "work packet creation rejects duplicate source graph item ids before inserting joins" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    assert {:error, error} =
             create_packet_with_operation(bootstrap.session, "duplicate-source-reference", %{
               title: "Duplicate source packet",
               objective: "Reject duplicate source references.",
               context_summary: "Packet source references must be unique.",
               requirements: "Use each source graph item once.",
               success_criteria: "Validation returns an error before source inserts.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [
                 verification_check.graph_item_id,
                 verification_check.graph_item_id
               ],
               verification_check_ids: [verification_check.id]
             })

    assert Exception.message(error) =~ "source_graph_item_ids must not include duplicate ids"
  end

  test "work packet creation rejects checks already satisfied by direct verification" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, completion_operation} =
      Operations.start_operation(bootstrap.session, :verification_complete,
        idempotency_key: "packet-create-satisfied-check"
      )

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               completion_operation,
               verification_check,
               %{
                 title: "Satisfied before packet creation",
                 body: "Direct completion satisfies the check before packet handoff.",
                 artifact_uri: "https://example.test/packet-create-satisfied-check"
               }
             )

    assert completed.verification_check.lifecycle_state == "satisfied"

    assert {:error, error} =
             create_packet_with_operation(bootstrap.session, "satisfied-required-check", %{
               title: "Satisfied check packet",
               objective: "Reject satisfied checks.",
               context_summary: "Packet creation only accepts required checks.",
               requirements: "Use checks that still need verification.",
               success_criteria: "Validation returns an error before packet creation.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [verification_check.graph_item_id],
               verification_check_ids: [verification_check.id]
             })

    assert Exception.message(error) =~
             "verification_check_ids must reference required verification checks"
  end

  test "direct required-check creates reject foreign packet versions" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Required Check Direct Scope A",
        workspace_slug: "required-check-direct-scope-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Required Check Direct Scope B",
        workspace_slug: "required-check-direct-scope-b"
      )

    {:ok, verification_check} = create_required_verification_check(first_scope.session)
    {:ok, foreign_check} = create_required_verification_check(second_scope.session)
    {:ok, foreign_packet} = create_ready_packet(second_scope.session, [foreign_check])

    assert {:error, error} =
             Ash.create(
               WorkPacketRequiredCheck,
               %{
                 id: Ecto.UUID.generate(),
                 work_packet_version_id: foreign_packet.version.id,
                 verification_check_id: verification_check.id,
                 organization_id: first_scope.session.organization_id,
                 workspace_id: first_scope.session.workspace_id
               },
               actor: first_scope.session,
               action: :create
             )

    assert Exception.message(error) =~ "work_packet_version_id"
  end

  test "direct source-reference creates reject foreign packet versions" do
    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Source Reference Direct Scope A",
        workspace_slug: "source-reference-direct-scope-a"
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Source Reference Direct Scope B",
        workspace_slug: "source-reference-direct-scope-b"
      )

    {:ok, verification_check} = create_required_verification_check(first_scope.session)
    {:ok, foreign_check} = create_required_verification_check(second_scope.session)
    {:ok, foreign_packet} = create_ready_packet(second_scope.session, [foreign_check])

    assert {:error, error} =
             Ash.create(
               WorkPacketSourceReference,
               %{
                 id: Ecto.UUID.generate(),
                 work_packet_version_id: foreign_packet.version.id,
                 graph_item_id: verification_check.graph_item_id,
                 organization_id: first_scope.session.organization_id,
                 workspace_id: first_scope.session.workspace_id
               },
               actor: first_scope.session,
               action: :create
             )

    assert Exception.message(error) =~ "work_packet_version_id"
  end

  test "packet contract join creates are private" do
    for resource <- [
          WorkPacketSourceReference,
          WorkPacketRequiredCheck
        ] do
      action = Ash.Resource.Info.action(resource, :create)

      refute action.public?,
             "#{inspect(resource)}.create must stay behind the packet creation command"
    end
  end

  test "domain-owned packet-run create actions are private" do
    for resource <- [
          WorkPacket,
          Run,
          RunRequiredCheck,
          ExecutionObservation,
          WorkPacketVersion,
          EvidenceCandidate,
          EvidenceItem
        ] do
      action = Ash.Resource.Info.action(resource, :create)

      refute action.public?,
             "#{inspect(resource)}.create must stay behind the owning domain command"
    end
  end

  test "direct run creates derive initial lifecycle state" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "direct-run-create-derived-lifecycle"
      )

    completed_at = DateTime.utc_now()

    assert {:ok, run} =
             Ash.create(
               Run,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 work_packet_id: packet_result.packet.id,
                 work_packet_version_id: packet_result.version.id,
                 operation_id: run_operation.id,
                 initiator_principal_id: bootstrap.session.principal_id,
                 objective: packet_result.version.objective,
                 authority_posture: "human_supervised",
                 source_surface: "test",
                 reason: "Direct creates derive their initial lifecycle."
               },
               actor: bootstrap.session,
               action: :create
             )

    assert run.state == "running"
    assert run.aggregate_state == "running"
    assert run.execution_state == "pending"
    assert run.verification_state == "unverified"
    assert is_nil(run.completed_at)
    assert DateTime.compare(run.started_at, completed_at) != :lt
  end

  test "direct run creates reject caller supplied lifecycle state" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "direct-run-create-rejects-lifecycle-input"
      )

    assert {:error, error} =
             Ash.create(
               Run,
               %{
                 id: Ecto.UUID.generate(),
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 work_packet_id: packet_result.packet.id,
                 work_packet_version_id: packet_result.version.id,
                 operation_id: run_operation.id,
                 initiator_principal_id: bootstrap.session.principal_id,
                 objective: packet_result.version.objective,
                 authority_posture: "human_supervised",
                 source_surface: "test",
                 reason: "Direct creates cannot choose terminal lifecycle.",
                 state: "verified"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "No such input `state`"
  end

  test "direct run creates reject packet versions that are not ready" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "direct-draft-packet-run"
      )

    assert {:ok, packet_result} =
             WorkPackets.create_packet(bootstrap.session, packet_operation, %{
               title: "Direct incomplete packet",
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
        idempotency_key: "direct-draft-packet-run"
      )

    assert {:error, error} =
             Ash.create(
               Run,
               direct_run_attrs(bootstrap.session, packet_result, run_operation),
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"
  end

  test "direct run creates reject malformed ready packet versions without execution links" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "direct-malformed-ready-packet-version"
      )

    packet_id = Ecto.UUID.generate()
    version_id = Ecto.UUID.generate()

    {:ok, packet} =
      Ash.create(
        WorkPacket,
        %{
          id: packet_id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: packet_operation.id,
          title: "Direct malformed ready packet"
        },
        action: :create,
        authorize?: false
      )

    {:ok, version} =
      Ash.create(
        WorkPacketVersion,
        %{
          id: version_id,
          work_packet_id: packet.id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: packet_operation.id,
          version_number: 1,
          title: "Malformed packet version",
          objective: "Malformed ready packet version.",
          context_summary: "Missing source and required-check rows.",
          requirements: "Should not be executable.",
          success_criteria: "All required checks pass.",
          autonomy_posture: "human_supervised",
          source_graph_item_ids: [verification_check.graph_item_id],
          verification_check_ids: [verification_check.id]
        },
        action: :create,
        authorize?: false
      )

    assert version.lifecycle_state == "ready"

    {:ok, packet} =
      packet
      |> Ash.Changeset.for_update(:set_current_version, %{current_version_id: version_id})
      |> Ash.update(authorize?: false)

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "direct-malformed-ready-packet-version-run"
      )

    assert {:error, error} =
             Ash.create(
               Run,
               direct_run_attrs(
                 bootstrap.session,
                 %{packet: packet, version: version},
                 run_operation
               ),
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"
  end

  test "direct run creates reject malformed ready packet versions with mismatched source checks" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, source_check} = create_required_verification_check(bootstrap.session)
    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "direct-mismatched-ready-packet-version"
      )

    packet_id = Ecto.UUID.generate()
    version_id = Ecto.UUID.generate()

    {:ok, packet} =
      Ash.create(
        WorkPacket,
        %{
          id: packet_id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: packet_operation.id,
          title: "Direct mismatched ready packet"
        },
        action: :create,
        authorize?: false
      )

    {:ok, version} =
      Ash.create(
        WorkPacketVersion,
        %{
          id: version_id,
          work_packet_id: packet.id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id,
          operation_id: packet_operation.id,
          version_number: 1,
          title: "Mismatched packet version",
          objective: "Malformed ready packet version.",
          context_summary: "Rows exist, but the selected check is unrelated to the source.",
          requirements: "Should not be executable.",
          success_criteria: "All required checks pass.",
          autonomy_posture: "human_supervised",
          source_graph_item_ids: [source_check.graph_item_id],
          verification_check_ids: [unrelated_check.id]
        },
        action: :create,
        authorize?: false
      )

    assert version.lifecycle_state == "ready"

    {:ok, _source_reference} =
      Ash.create(
        WorkPacketSourceReference,
        %{
          id: Ecto.UUID.generate(),
          work_packet_version_id: version.id,
          graph_item_id: source_check.graph_item_id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id
        },
        action: :create,
        authorize?: false
      )

    {:ok, _required_check} =
      Ash.create(
        WorkPacketRequiredCheck,
        %{
          id: Ecto.UUID.generate(),
          work_packet_version_id: version.id,
          verification_check_id: unrelated_check.id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id
        },
        action: :create,
        authorize?: false
      )

    {:ok, packet} =
      packet
      |> Ash.Changeset.for_update(:set_current_version, %{current_version_id: version_id})
      |> Ash.update(authorize?: false)

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "direct-mismatched-ready-packet-version-run"
      )

    assert {:error, error} =
             Ash.create(
               Run,
               direct_run_attrs(
                 bootstrap.session,
                 %{packet: packet, version: version},
                 run_operation
               ),
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~
             "work_packet_version_id must reference a ready packet version"
  end

  test "direct run creates reject authority outside the packet autonomy envelope" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [verification_check])

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "direct-run-authority-envelope"
      )

    attrs =
      bootstrap.session
      |> direct_run_attrs(packet_result, run_operation)
      |> Map.put(:authority_posture, "fully_autonomous")

    assert {:error, error} =
             Ash.create(
               Run,
               attrs,
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~
             "authority_posture must match the packet autonomy posture"
  end

  test "direct run creates reject packet and version mismatches" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, first_packet} = create_ready_packet(bootstrap.session, [first_check])
    {:ok, second_packet} = create_ready_packet(bootstrap.session, [second_check])

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "direct-run-packet-version-mismatch"
      )

    attrs =
      bootstrap.session
      |> direct_run_attrs(
        %{packet: first_packet.packet, version: second_packet.version},
        run_operation
      )
      |> Map.put(:objective, second_packet.version.objective)

    assert {:error, error} =
             Ash.create(
               Run,
               attrs,
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "work_packet_version_id must belong to work_packet_id"
  end

  test "direct run required-check creates reject checks outside the run packet contract" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, required_check} = create_required_verification_check(bootstrap.session)
    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, required_check)

    assert {:error, error} =
             Ash.create(
               RunRequiredCheck,
               %{
                 id: Ecto.UUID.generate(),
                 run_id: run_result.run.id,
                 verification_check_id: unrelated_check.id,
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "verification_check_id"
  end

  test "direct run required-check creates derive pending state" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    delete_run_required_check!(run_result.run.id, verification_check.id)

    assert {:ok, required_check} =
             Ash.create(
               RunRequiredCheck,
               %{
                 id: Ecto.UUID.generate(),
                 run_id: run_result.run.id,
                 verification_check_id: verification_check.id,
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id
               },
               actor: bootstrap.session,
               action: :create
             )

    assert required_check.state == "pending"
  end

  test "direct run required-check creates reject caller supplied state" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    delete_run_required_check!(run_result.run.id, verification_check.id)

    assert {:error, error} =
             Ash.create(
               RunRequiredCheck,
               %{
                 id: Ecto.UUID.generate(),
                 run_id: run_result.run.id,
                 verification_check_id: verification_check.id,
                 organization_id: bootstrap.session.organization_id,
                 workspace_id: bootstrap.session.workspace_id,
                 state: "satisfied"
               },
               actor: bootstrap.session,
               action: :create
             )

    assert Exception.message(error) =~ "No such input `state`"
  end
end
