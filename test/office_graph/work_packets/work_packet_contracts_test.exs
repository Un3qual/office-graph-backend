defmodule OfficeGraph.WorkPackets.WorkPacketContractsTest do
  use OfficeGraph.TestSupport.WorkPacketCommandLoopSupport

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

    assert AuthorizationDecision
           |> Ash.Query.filter(
             operation_id == ^stale_operation.id and action == "verification.waive" and
               decision == "allow"
           )
           |> Ash.exists?(authorize?: false)

    refute VerificationResult
           |> Ash.Query.filter(operation_id == ^stale_operation.id)
           |> Ash.exists?(authorize?: false)

    assert "pending" ==
             RunRequiredCheck
             |> Ash.get!(first_required_check.id, authorize?: false)
             |> Map.fetch!(:state)

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

  test "run required-check validation sanitizes lookup failures" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    changeset = fn run_id, verification_check_id ->
      %Ash.Changeset{
        arguments: %{},
        attributes: %{
          run_id: run_id,
          verification_check_id: verification_check_id,
          organization_id: bootstrap.session.organization_id,
          workspace_id: bootstrap.session.workspace_id
        }
      }
    end

    [invalid_run] =
      ValidateRunRequiredCheckContract.batch_change(
        [changeset.("not-a-run-uuid", verification_check.id)],
        [],
        %{}
      )

    assert Enum.any?(invalid_run.errors, fn error ->
             error.field == :run_id and error.message == "run_id could not be validated"
           end)

    refute Enum.any?(invalid_run.errors, &String.contains?(&1.message, "not-a-run-uuid"))

    [failed_check_lookup] =
      ValidateRunRequiredCheckContract.batch_change(
        [changeset.(run_result.run.id, verification_check.id)],
        [
          packet_required_check_reader: fn _changesets, _runs_by_id ->
            {:error, RuntimeError.exception("private packet lookup failure")}
          end
        ],
        %{}
      )

    assert Enum.any?(failed_check_lookup.errors, fn error ->
             error.field == :verification_check_id and
               error.message == "verification_check_id could not be validated"
           end)

    refute Enum.any?(failed_check_lookup.errors, fn error ->
             String.contains?(error.message, "private packet lookup failure")
           end)
  end
end
