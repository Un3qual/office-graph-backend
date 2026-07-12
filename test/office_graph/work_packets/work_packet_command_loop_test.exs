defmodule OfficeGraph.WorkPackets.WorkPacketCommandLoopTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.QueryCounter
  alias OfficeGraph.Runs
  alias OfficeGraph.Runs.Changes.ValidateRunRequiredCheckContract
  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.{Audit, Repo, Revisions}

  alias OfficeGraph.WorkGraph.{
    Artifact,
    EvidenceItem,
    EvidenceCandidate,
    GraphItem,
    GraphRelationship,
    ReviewFinding,
    Task,
    VerificationResult
  }

  alias OfficeGraph.WorkPackets

  alias OfficeGraph.WorkPackets.{
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

  require Ash.Query

  test "packet collection writes keep query count bounded" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    verification_checks =
      Enum.map(1..4, fn _index ->
        {:ok, verification_check} = create_required_verification_check(bootstrap.session)
        verification_check
      end)

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create)

    {{:ok, packet_result}, packet_queries} =
      QueryCounter.count(fn ->
        WorkPackets.create_packet(bootstrap.session, packet_operation, %{
          title: "Bulk query packet",
          objective: "Bound packet collection writes.",
          context_summary: "Multiple packet references.",
          requirements: "Create all references atomically.",
          success_criteria: "One Ash batch per link resource.",
          autonomy_posture: "human_supervised",
          source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
          verification_check_ids: Enum.map(verification_checks, & &1.id)
        })
      end)

    assert length(packet_result.source_references) == 4
    assert length(packet_result.required_checks) == 4

    # Accepted budget: one insert per link resource within an Ash batch. Query
    # count may grow by configured batch count, never by individual input row.
    assert QueryCounter.source_count(packet_queries, "work_packet_version_sources") <= 1

    assert QueryCounter.source_count(
             packet_queries,
             "work_packet_version_required_checks"
           ) <= 1

    assert QueryCounter.source_count(packet_queries, "graph_items") <= 1
    assert QueryCounter.source_count(packet_queries, "verification_checks") <= 2
    # Version reads cover the parent create plus the two child validators, but
    # stay fixed as the number of child inputs grows.
    assert QueryCounter.source_count(packet_queries, "work_packet_versions") <= 5
  end

  test "packet and run collection order survives idempotent replay" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    verification_checks =
      Enum.map(1..4, fn _index ->
        {:ok, verification_check} = create_required_verification_check(bootstrap.session)
        verification_check
      end)

    packet_attrs = %{
      title: "Ordered packet",
      objective: "Preserve packet child order.",
      context_summary: "Bulk children need a durable order.",
      requirements: "Return links in caller input order.",
      success_criteria: "Packet and run replay order is stable.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
      verification_check_ids: Enum.map(verification_checks, & &1.id)
    }

    {:ok, packet_operation} =
      Operations.start_operation(bootstrap.session, :work_packet_create,
        idempotency_key: "ordered-packet-replay"
      )

    assert {:ok, first_packet_result} =
             WorkPackets.create_packet(bootstrap.session, packet_operation, packet_attrs)

    assert {:ok, replayed_packet_result} =
             WorkPackets.create_packet(bootstrap.session, packet_operation, packet_attrs)

    expected_source_ids = packet_attrs.source_graph_item_ids
    expected_check_ids = packet_attrs.verification_check_ids

    for packet_result <- [first_packet_result, replayed_packet_result] do
      assert Enum.map(packet_result.source_references, & &1.position) == Enum.to_list(0..3)
      assert Enum.map(packet_result.source_references, & &1.graph_item_id) == expected_source_ids
      assert Enum.map(packet_result.required_checks, & &1.position) == Enum.to_list(0..3)

      assert Enum.map(packet_result.required_checks, & &1.verification_check_id) ==
               expected_check_ids
    end

    {:ok, run_operation} =
      Operations.start_operation(bootstrap.session, :work_run_start,
        idempotency_key: "ordered-run-replay"
      )

    run_attrs = %{
      source_surface: "test",
      reason: "Prove durable required-check order.",
      authority_posture: "human_supervised"
    }

    assert {:ok, first_run_result} =
             Runs.start_run(
               bootstrap.session,
               run_operation,
               first_packet_result.version,
               run_attrs
             )

    assert {:ok, replayed_run_result} =
             Runs.start_run(
               bootstrap.session,
               run_operation,
               first_packet_result.version,
               run_attrs
             )

    for run_result <- [first_run_result, replayed_run_result] do
      assert Enum.map(run_result.required_checks, & &1.position) == Enum.to_list(0..3)

      assert Enum.map(run_result.required_checks, & &1.verification_check_id) ==
               expected_check_ids
    end
  end

  test "packet versions are immutable, ordered, replayable, and concurrency guarded" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [first_check])

    assert packet_result.version.title == "Ready packet"

    version_attrs = %{
      expected_current_version_id: packet_result.version.id,
      title: "Revised packet",
      objective: "Run the revised selected work.",
      context_summary: "Revised ready context.",
      requirements: "Complete the revised selected work.",
      success_criteria: "Both required checks pass.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: [second_check.graph_item_id, first_check.graph_item_id],
      verification_check_ids: [second_check.id, first_check.id]
    }

    command_input = Map.put(version_attrs, :packet_id, packet_result.packet.id)

    assert {:ok, operation} =
             Operations.start_command(
               bootstrap.session,
               :work_packet_version_create,
               "packet-version-2",
               command_input
             )

    assert {:ok, revised} =
             WorkPackets.create_version(
               bootstrap.session,
               operation,
               packet_result.packet,
               version_attrs
             )

    assert revised.version.version_number == 2
    assert revised.version.title == "Revised packet"
    assert revised.packet.title == "Revised packet"
    assert revised.packet.current_version_id == revised.version.id

    assert Enum.map(revised.source_references, & &1.graph_item_id) ==
             version_attrs.source_graph_item_ids

    assert Enum.map(revised.required_checks, & &1.verification_check_id) ==
             version_attrs.verification_check_ids

    assert {:ok, replayed} =
             WorkPackets.create_version(
               bootstrap.session,
               operation,
               packet_result.packet,
               version_attrs
             )

    assert replayed.version.id == revised.version.id

    reordered_attrs = %{
      version_attrs
      | source_graph_item_ids: Enum.reverse(version_attrs.source_graph_item_ids),
        verification_check_ids: Enum.reverse(version_attrs.verification_check_ids)
    }

    assert {:error, {:command_idempotency_conflict, operation_id}} =
             WorkPackets.create_version(
               bootstrap.session,
               operation,
               revised.packet,
               reordered_attrs
             )

    assert operation_id == operation.id

    stale_attrs = %{version_attrs | title: "Stale packet"}
    stale_input = Map.put(stale_attrs, :packet_id, packet_result.packet.id)

    assert {:ok, stale_operation} =
             Operations.start_command(
               bootstrap.session,
               :work_packet_version_create,
               "packet-version-stale",
               stale_input
             )

    assert {:error, {:stale_packet_version, packet_id, actual_current_version_id}} =
             WorkPackets.create_version(
               bootstrap.session,
               stale_operation,
               revised.packet,
               stale_attrs
             )

    assert packet_id == packet_result.packet.id
    assert actual_current_version_id == revised.version.id

    next_attrs = %{
      version_attrs
      | expected_current_version_id: revised.version.id,
        title: "Third packet version"
    }

    assert {:ok, next_operation} =
             Operations.start_command(
               bootstrap.session,
               :work_packet_version_create,
               "packet-version-3",
               Map.put(next_attrs, :packet_id, packet_result.packet.id)
             )

    assert {:ok, next} =
             WorkPackets.create_version(
               bootstrap.session,
               next_operation,
               revised.packet,
               next_attrs
             )

    assert next.version.version_number == 3
    assert next.version.title == "Third packet version"

    original_packet_operation =
      Ash.get!(
        OfficeGraph.Operations.OperationCorrelation,
        packet_result.packet.operation_id,
        authorize?: false
      )

    assert {:ok, replayed_create} =
             WorkPackets.create_packet(bootstrap.session, original_packet_operation, %{
               title: "Ready packet",
               objective: "Run selected work.",
               context_summary: "Ready context.",
               requirements: "Complete selected work.",
               success_criteria: "Required checks pass.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [first_check.graph_item_id],
               verification_check_ids: [first_check.id]
             })

    assert replayed_create.version.id == packet_result.version.id
    assert replayed_create.version.version_number == 1
    assert replayed_create.packet.current_version_id == next.version.id
  end

  test "governed verification waivers are replayable, audited, and recompute run state" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    assert {:ok, observation_result} =
             record_observation(
               bootstrap.session,
               run_result.run,
               verification_check,
               key: "waiver-success-observation"
             )

    run = observation_result.run
    [required_check] = run_result.required_checks

    waiver_attrs = %{
      expected_execution_state: run.execution_state,
      expected_verification_state: run.verification_state,
      reason: "Approved exception for unavailable external proof.",
      policy_basis: "owner_exception"
    }

    command_input =
      waiver_attrs
      |> Map.put(:run_id, run.id)
      |> Map.put(:run_required_check_id, required_check.id)

    assert {:ok, operation} =
             Operations.start_command(
               bootstrap.session,
               :verification_waive,
               "waiver-success",
               command_input
             )

    assert {:ok, waived} =
             Verification.waive_required_check(
               bootstrap.session,
               operation,
               run,
               required_check,
               waiver_attrs
             )

    assert waived.verification_result.result == "waived"
    assert waived.verification_result.evidence_item_id == nil
    assert waived.verification_result.actor_principal_id == bootstrap.session.principal_id
    assert waived.verification_result.reason == waiver_attrs.reason
    assert waived.verification_result.policy_basis == waiver_attrs.policy_basis
    assert waived.required_check.state == "waived"
    assert waived.run.verification_state == "verified"
    assert waived.run.aggregate_state == "verified"

    assert {:ok, summary} = Runs.get_summary(bootstrap.session, waived.run.id)
    assert summary.missing_evidence == []

    assert Audit.count_for_operation(operation.id) >= 2
    assert Revisions.count_for_operation(operation.id) >= 2

    assert {:ok, replayed} =
             Verification.waive_required_check(
               bootstrap.session,
               operation,
               waived.run,
               required_check,
               waiver_attrs
             )

    assert replayed.verification_result.id == waived.verification_result.id
    assert replayed.required_check.id == waived.required_check.id

    changed_attrs = %{waiver_attrs | reason: "A changed exception reason."}

    assert {:error, {:command_idempotency_conflict, operation_id}} =
             Verification.waive_required_check(
               bootstrap.session,
               operation,
               waived.run,
               required_check,
               changed_attrs
             )

    assert operation_id == operation.id

    assert {:ok, already_waived_operation} =
             Operations.start_command(
               bootstrap.session,
               :verification_waive,
               "waiver-already-complete",
               command_input
             )

    assert {:error, {:run_required_check_not_pending, required_check_id, "waived"}} =
             Verification.waive_required_check(
               bootstrap.session,
               already_waived_operation,
               waived.run,
               required_check,
               waiver_attrs
             )

    assert required_check_id == required_check.id
  end

  test "verification waivers reject stale runs, wrong checks, and preserve other pending checks" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, [first_check, second_check])

    assert {:ok, observation_result} =
             record_observation(
               bootstrap.session,
               run_result.run,
               first_check,
               key: "waiver-multi-observation"
             )

    run = observation_result.run
    [first_required_check, second_required_check] = run_result.required_checks

    stale_attrs = %{
      expected_execution_state: "pending",
      expected_verification_state: run.verification_state,
      reason: "Stale waiver request.",
      policy_basis: "owner_exception"
    }

    assert {:ok, stale_operation} =
             start_waiver_command(
               bootstrap.session,
               "waiver-stale",
               run,
               first_required_check,
               stale_attrs
             )

    assert {:error, {:stale_work_run_state, run_id, execution_state, verification_state}} =
             Verification.waive_required_check(
               bootstrap.session,
               stale_operation,
               run,
               first_required_check,
               stale_attrs
             )

    assert run_id == run.id
    assert execution_state == run.execution_state
    assert verification_state == run.verification_state

    {:ok, other_check} = create_required_verification_check(bootstrap.session)
    {:ok, other_run_result} = create_ready_run(bootstrap.session, other_check)
    [other_required_check] = other_run_result.required_checks

    valid_attrs = %{
      expected_execution_state: run.execution_state,
      expected_verification_state: run.verification_state,
      reason: "Approved exception for the first check.",
      policy_basis: "owner_exception"
    }

    assert {:ok, wrong_check_operation} =
             start_waiver_command(
               bootstrap.session,
               "waiver-wrong-check",
               run,
               other_required_check,
               valid_attrs
             )

    assert {:error, {:run_required_check_mismatch, run_id, required_check_id}} =
             Verification.waive_required_check(
               bootstrap.session,
               wrong_check_operation,
               run,
               other_required_check,
               valid_attrs
             )

    assert run_id == run.id
    assert required_check_id == other_required_check.id

    assert {:ok, operation} =
             start_waiver_command(
               bootstrap.session,
               "waiver-multi-first",
               run,
               first_required_check,
               valid_attrs
             )

    assert {:ok, waived} =
             Verification.waive_required_check(
               bootstrap.session,
               operation,
               run,
               first_required_check,
               valid_attrs
             )

    assert waived.required_check.state == "waived"
    assert waived.run.verification_state == "missing_evidence"
    refute waived.run.aggregate_state == "verified"

    assert "pending" ==
             RunRequiredCheck
             |> Ash.get!(second_required_check.id, authorize?: false)
             |> Map.fetch!(:state)
  end

  test "packet source bulk create rolls back an invalid middle reference" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    verification_checks =
      Enum.map(1..3, fn _index ->
        {:ok, verification_check} = create_required_verification_check(bootstrap.session)
        verification_check
      end)

    [packet_check, first_extra_check, second_extra_check] = verification_checks
    {:ok, packet_result} = create_ready_packet(bootstrap.session, [packet_check])

    inputs =
      Enum.map(
        [
          first_extra_check.graph_item_id,
          Ecto.UUID.generate(),
          second_extra_check.graph_item_id
        ],
        fn graph_item_id ->
          %{
            id: Ecto.UUID.generate(),
            work_packet_version_id: packet_result.version.id,
            graph_item_id: graph_item_id,
            organization_id: bootstrap.session.organization_id,
            workspace_id: bootstrap.session.workspace_id
          }
        end
      )

    assert {:error, %Ash.Error.Invalid{}} =
             Repo.transaction(fn ->
               Repo.ash_bulk_create!(WorkPacketSourceReference, inputs)
             end)

    input_ids = Enum.map(inputs, & &1.id)

    assert [] ==
             WorkPacketSourceReference
             |> Ash.Query.filter(id in ^input_ids)
             |> Ash.read!(authorize?: false)
  end

  test "run required-check writes keep query count bounded" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    verification_checks =
      Enum.map(1..4, fn _index ->
        {:ok, verification_check} = create_required_verification_check(bootstrap.session)
        verification_check
      end)

    {:ok, packet_result} = create_ready_packet(bootstrap.session, verification_checks)
    {:ok, run_operation} = Operations.start_operation(bootstrap.session, :work_run_start)

    {{:ok, run_result}, run_queries} =
      QueryCounter.count(fn ->
        Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
          source_surface: "test",
          reason: "Exercise bulk required checks.",
          authority_posture: "human_supervised"
        })
      end)

    assert length(run_result.required_checks) == 4

    # Accepted budget: one insert per Ash batch, not one insert per required check.
    assert QueryCounter.source_count(run_queries, "run_required_checks") <= 1
  end

  test "run required-check bulk create rolls back an invalid middle contract" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    packet_checks =
      Enum.map(1..3, fn _index ->
        {:ok, verification_check} = create_required_verification_check(bootstrap.session)
        verification_check
      end)

    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, packet_checks)

    Enum.each(packet_checks, fn verification_check ->
      delete_run_required_check!(run_result.run.id, verification_check.id)
    end)

    [first_check, second_check | _rest] = packet_checks

    inputs =
      Enum.map([first_check, unrelated_check, second_check], fn verification_check ->
        %{
          id: Ecto.UUID.generate(),
          run_id: run_result.run.id,
          verification_check_id: verification_check.id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id
        }
      end)

    assert {:error, %Ash.Error.Invalid{}} =
             Repo.transaction(fn -> Repo.ash_bulk_create!(RunRequiredCheck, inputs) end)

    input_ids = Enum.map(inputs, & &1.id)

    assert [] ==
             RunRequiredCheck
             |> Ash.Query.filter(id in ^input_ids)
             |> Ash.read!(authorize?: false)
  end

  test "run required-check contract batches validation reads" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    verification_checks =
      Enum.map(1..4, fn _index ->
        {:ok, verification_check} = create_required_verification_check(bootstrap.session)
        verification_check
      end)

    {:ok, run_result} = create_ready_run(bootstrap.session, verification_checks)

    Enum.each(verification_checks, fn verification_check ->
      delete_run_required_check!(run_result.run.id, verification_check.id)
    end)

    inputs =
      Enum.map(verification_checks, fn verification_check ->
        %{
          id: Ecto.UUID.generate(),
          run_id: run_result.run.id,
          verification_check_id: verification_check.id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id
        }
      end)

    {%Ash.BulkResult{status: :success, records: records}, queries} =
      QueryCounter.count(fn ->
        Ash.bulk_create(inputs, RunRequiredCheck, :create,
          actor: bootstrap.session,
          authorize?: true,
          return_errors?: true,
          return_records?: true,
          sorted?: true,
          stop_on_error?: true
        )
      end)

    assert length(records) == 4

    # SameScopeReferences reads runs once; the run contract reads them once.
    assert QueryCounter.source_count(queries, "runs") <= 2

    assert QueryCounter.source_count(
             queries,
             "work_packet_version_required_checks"
           ) <= 1
  end

  test "run required-check contract preserves bulk packet mismatch errors" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, required_check} = create_required_verification_check(bootstrap.session)
    {:ok, unrelated_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, required_check)

    delete_run_required_check!(run_result.run.id, required_check.id)

    inputs =
      Enum.map([required_check, unrelated_check], fn verification_check ->
        %{
          id: Ecto.UUID.generate(),
          run_id: run_result.run.id,
          verification_check_id: verification_check.id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id
        }
      end)

    assert %Ash.BulkResult{status: :partial_success, error_count: 1, errors: [error]} =
             Ash.bulk_create(inputs, RunRequiredCheck, :create,
               actor: bootstrap.session,
               authorize?: true,
               return_errors?: true,
               return_records?: true,
               sorted?: true
             )

    assert Exception.message(error) =~
             "verification_check_id must belong to the run packet version"
  end

  test "run required-check batch validation preserves run reference errors" do
    {:ok, actor_scope} = bootstrap_local_owner_for("run-contract-errors-actor")
    {:ok, other_scope} = bootstrap_local_owner_for("run-contract-errors-other")
    {:ok, actor_check} = create_required_verification_check(actor_scope.session)
    {:ok, other_check} = create_required_verification_check(other_scope.session)
    {:ok, other_run_result} = create_ready_run(other_scope.session, other_check)
    {:ok, actor_packet_result} = create_ready_packet(actor_scope.session, [actor_check])

    non_packet_run_id =
      insert_non_packet_run!(actor_scope.session, actor_packet_result.packet.id)

    changesets =
      [
        Ecto.UUID.generate(),
        other_run_result.run.id,
        non_packet_run_id
      ]
      |> Enum.map(fn run_id ->
        %Ash.Changeset{
          arguments: %{},
          attributes: %{
            run_id: run_id,
            verification_check_id: actor_check.id,
            organization_id: actor_scope.session.organization_id,
            workspace_id: actor_scope.session.workspace_id
          }
        }
      end)

    [missing_run, cross_scope_run, non_packet_run] =
      ValidateRunRequiredCheckContract.batch_change(changesets, [], %{})

    assert Enum.any?(missing_run.errors, fn error ->
             error.message == "run_id must reference an existing run in the target scope"
           end)

    assert Enum.any?(cross_scope_run.errors, fn error ->
             error.message == "run_id must reference an existing run in the target scope"
           end)

    assert Enum.any?(non_packet_run.errors, fn error ->
             error.message == "run_id must reference a packet-backed run"
           end)
  end

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
             "has_evidence"
           )

    assert relationship_exists?(
             accepted.evidence_item.graph_item_id,
             artifact.graph_item_id,
             "references_artifact"
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

  test "verified runs stay verified after later failed observations" do
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

    assert later_observation.run.aggregate_state == "verified"
    assert later_observation.run.execution_state == "completed"
    assert later_observation.run.verification_state == "verified"

    {:ok, summary} = Runs.get_summary(bootstrap.session, accepted.work_run.id)
    assert summary.run.aggregate_state == "verified"
    assert summary.run.execution_state == "completed"
    assert summary.run.verification_state == "verified"
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

    assert {:error, {:work_run_already_verified, ^run_id}} =
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

  defp create_packet_with_operation(session, idempotency_key, attrs) do
    {:ok, operation} =
      Operations.start_operation(session, :work_packet_create, idempotency_key: idempotency_key)

    WorkPackets.create_packet(session, operation, attrs)
  end

  defp start_waiver_command(session, key, run, required_check, attrs) do
    command_input =
      attrs
      |> Map.put(:run_id, run.id)
      |> Map.put(:run_required_check_id, required_check.id)

    Operations.start_command(session, :verification_waive, key, command_input)
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

  defp direct_run_attrs(session, packet_result, operation) do
    %{
      id: Ecto.UUID.generate(),
      organization_id: session.organization_id,
      workspace_id: session.workspace_id,
      work_packet_id: packet_result.packet.id,
      work_packet_version_id: packet_result.version.id,
      operation_id: operation.id,
      initiator_principal_id: session.principal_id,
      objective: packet_result.version.objective,
      authority_posture: "human_supervised",
      source_surface: "test",
      reason: "Direct run create validates the packet contract."
    }
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
      artifact_id: Keyword.get(opts, :artifact_id),
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

  defp relationship_exists?(source_item_id, target_item_id, relationship_type) do
    GraphRelationship
    |> Ash.Query.filter(
      source_item_id == ^source_item_id and target_item_id == ^target_item_id and
        relationship_type == ^relationship_type
    )
    |> Ash.exists?(authorize?: false)
  end

  defp accepted_evidence_for_candidate?(candidate_id) do
    EvidenceItem
    |> Ash.Query.filter(candidate_id == ^candidate_id)
    |> Ash.exists?(authorize?: false)
  end

  defp run_for_operation?(operation_id) do
    Run
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.exists?(authorize?: false)
  end

  defp verification_result_for_candidate_target?(candidate) do
    VerificationResult
    |> Ash.Query.filter(
      verification_check_id == ^candidate.verification_check_id and
        work_run_id == ^candidate.work_run_id
    )
    |> Ash.exists?(authorize?: false)
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

  defp insert_malformed_execution_observation!(session, operation, run, verification_check) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO execution_observations (
        id,
        organization_id,
        workspace_id,
        work_run_id,
        operation_id,
        verification_check_id,
        graph_item_id,
        source_kind,
        source_identity,
        idempotency_key,
        observed_status,
        normalized_status,
        ingested_at,
        freshness_state,
        trust_basis,
        rationale,
        metadata,
        inserted_at,
        updated_at
      )
      VALUES (
        $1::uuid,
        $2::uuid,
        $3::uuid,
        $4::uuid,
        $5::uuid,
        $6::uuid,
        $7::uuid,
        'human',
        'manual:malformed-summary-observation',
        'malformed-summary-observation',
        'passed',
        'succeeded',
        $8,
        'fresh',
        'owner_attested',
        'Malformed legacy row.',
        '{}'::jsonb,
        $8,
        $8
      )
      """,
      [
        db_uuid(id),
        db_uuid(session.organization_id),
        db_uuid(session.workspace_id),
        db_uuid(run.id),
        db_uuid(operation.id),
        db_uuid(verification_check.id),
        db_uuid(verification_check.graph_item_id),
        now
      ]
    )

    id
  end

  defp delete_run_required_check!(run_id, verification_check_id) do
    Repo.query!(
      """
      DELETE FROM run_required_checks
      WHERE run_id = $1::uuid AND verification_check_id = $2::uuid
      """,
      [db_uuid(run_id), db_uuid(verification_check_id)]
    )
  end

  defp insert_non_packet_run!(session, work_packet_id) do
    run_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO runs (
        id,
        organization_id,
        workspace_id,
        work_packet_id,
        work_packet_version_id,
        state,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, NULL, 'running', NOW(), NOW())
      """,
      [
        db_uuid(run_id),
        db_uuid(session.organization_id),
        db_uuid(session.workspace_id),
        db_uuid(work_packet_id)
      ]
    )

    run_id
  end

  defp bootstrap_local_owner_for(suffix) do
    Foundation.bootstrap_local_owner(
      organization_name: "Organization #{suffix}",
      organization_slug: suffix,
      workspace_name: "Workspace #{suffix}",
      workspace_slug: "workspace-#{suffix}",
      initiative_name: "Initiative #{suffix}",
      initiative_slug: "initiative-#{suffix}",
      owner_email: "owner-#{suffix}@office-graph.local",
      owner_name: "Owner #{suffix}"
    )
  end

  defp forge_packet_current_version!(packet_id, version_id) do
    Repo.query!(
      """
      UPDATE work_packets
      SET current_version_id = $1::uuid
      WHERE id = $2::uuid
      """,
      [db_uuid(version_id), db_uuid(packet_id)]
    )
  end

  defp blank_packet_execution_context!(version_id) do
    Repo.query!(
      """
      UPDATE work_packet_versions
      SET context_summary = '', requirements = ''
      WHERE id = $1::uuid
      """,
      [db_uuid(version_id)]
    )
  end

  defp run_exists_for_operation?(operation_id) do
    Run
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.exists?(authorize?: false)
  end

  defp db_uuid(value), do: Ecto.UUID.dump!(value)
end
