defmodule OfficeGraph.Integrations.WorkflowStateConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  test "packet version writers serialize one winner and one stale result" do
    suffix = System.unique_integer([:positive])
    organization_slug = "packet-version-race-#{suffix}"
    owner_email = "packet-version-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, packet_result, checks, operations, attrs} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Packet Version Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Packet Version Race Workspace #{suffix}",
              workspace_slug: "packet-version-race-workspace-#{suffix}",
              owner_email: owner_email,
              owner_name: "Packet Version Race Owner"
            )

          {:ok, first_check} =
            create_concurrency_verification_check(bootstrap.session, "packet-first-#{suffix}")

          {:ok, second_check} =
            create_concurrency_verification_check(bootstrap.session, "packet-second-#{suffix}")

          {:ok, packet_result} =
            create_concurrency_ready_packet(bootstrap.session, [first_check], suffix)

          attrs = %{
            expected_current_version_id: packet_result.version.id,
            title: "Concurrent packet revision #{suffix}",
            objective: "Serialize concurrent packet revision.",
            context_summary: "Two owners start from one current version.",
            requirements: "Only one revision may advance the packet.",
            success_criteria: "One writer wins and one receives stale state.",
            autonomy_posture: "human_supervised",
            source_graph_item_ids: [first_check.graph_item_id, second_check.graph_item_id],
            verification_check_ids: [first_check.id, second_check.id]
          }

          operations =
            for attempt <- 1..2 do
              {:ok, operation} =
                Operations.start_command(
                  bootstrap.session,
                  :work_packet_version_create,
                  "packet-version-race-#{suffix}-#{attempt}",
                  Map.put(attrs, :packet_id, packet_result.packet.id)
                )

              operation
            end

          {bootstrap, packet_result, [first_check, second_check], operations, attrs}
        end)

      results =
        operations
        |> Enum.map(fn operation ->
          fn ->
            WorkPackets.create_version(
              bootstrap.session,
              operation,
              packet_result.packet,
              attrs
            )
          end
        end)
        |> run_concurrently()

      assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _result}, &1))

      assert [
               {:error, {:stale_packet_version, packet_id, actual_current_version_id}}
             ] = Enum.reject(results, &match?({:ok, _result}, &1))

      assert packet_id == packet_result.packet.id
      assert actual_current_version_id == winner.version.id
      assert winner.version.version_number == 2

      assert Enum.map(winner.required_checks, & &1.verification_check_id) ==
               Enum.map(checks, & &1.id)

      assert {:ok, current_packet} =
               with_unboxed_connection(fn ->
                 WorkPackets.get_packet_for_version_command(
                   bootstrap.session,
                   packet_result.packet.id
                 )
               end)

      assert current_packet.current_version_id == winner.version.id
    after
      with_unboxed_connection(fn ->
        ConcurrencyCleanup.cleanup_work_run_verification_scope!(organization_slug)
        ConcurrencyCleanup.cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "run writers serialize one active run per packet version" do
    suffix = System.unique_integer([:positive])
    organization_slug = "active-run-race-#{suffix}"
    owner_email = "active-run-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, packet_version, operations, attrs} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Active Run Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Active Run Race Workspace #{suffix}",
              workspace_slug: "active-run-race-workspace-#{suffix}",
              owner_email: owner_email,
              owner_name: "Active Run Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "active-run-#{suffix}")

          {:ok, packet_result} =
            create_concurrency_ready_packet(bootstrap.session, [verification_check], suffix)

          operations =
            for attempt <- 1..2 do
              {:ok, operation} =
                Operations.start_operation(bootstrap.session, :work_run_start,
                  idempotency_key: "active-run-race-#{suffix}-#{attempt}"
                )

              operation
            end

          attrs = %{
            source_surface: "concurrency_test",
            reason: "Compete to start the one active run.",
            authority_posture: "human_supervised"
          }

          {bootstrap, packet_result.version, operations, attrs}
        end)

      results =
        operations
        |> Enum.map(fn operation ->
          fn -> Runs.start_run(bootstrap.session, operation, packet_version, attrs) end
        end)
        |> run_concurrently()

      assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _result}, &1))

      assert [{:error, {:active_work_run, packet_version_id, active_run_id}}] =
               Enum.reject(results, &match?({:ok, _result}, &1))

      assert packet_version_id == packet_version.id
      assert active_run_id == winner.run.id

      assert {:ok, summary} =
               with_unboxed_connection(fn ->
                 Runs.get_summary(bootstrap.session, winner.run.id)
               end)

      assert summary.run.id == winner.run.id
      assert length(summary.required_checks) == 1
    after
      with_unboxed_connection(fn ->
        ConcurrencyCleanup.cleanup_work_run_verification_scope!(organization_slug)
        ConcurrencyCleanup.cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "proposal application has one graph winner and one typed stale loser" do
    suffix = System.unique_integer([:positive])
    organization_slug = "proposal-apply-race-#{suffix}"
    owner_email = "proposal-apply-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, intake, operations} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Proposal Apply Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Proposal Apply Race Workspace #{suffix}",
              workspace_slug: "proposal-apply-race-workspace-#{suffix}",
              owner_email: owner_email,
              owner_name: "Proposal Apply Race Owner"
            )

          {:ok, intake_operation} =
            Operations.start_operation(bootstrap.session, :manual_intake_submit)

          {:ok, intake} =
            Integrations.submit_manual_intake(bootstrap.session, intake_operation, %{
              source_identity: "manual:proposal-apply-race-#{suffix}",
              replay_identity: "paste:proposal-apply-race-#{suffix}",
              body: "Apply this proposal set exactly once under concurrent owners."
            })

          operations =
            for _attempt <- 1..2 do
              {:ok, operation} =
                Operations.start_operation(bootstrap.session, :proposed_change_apply)

              operation
            end

          {bootstrap, intake, operations}
        end)

      apply_input = %{
        normalized_event_id: intake.normalized_event.id,
        proposed_changes: intake.proposed_changes
      }

      results =
        operations
        |> Enum.map(fn operation ->
          fn -> ProposedChanges.apply_all(bootstrap.session, operation, apply_input) end
        end)
        |> run_concurrently()

      assert [{:ok, _winner}] = Enum.filter(results, &match?({:ok, _result}, &1))

      assert [{:error, {:invalid_proposed_change_status, stale_change_id}}] =
               Enum.reject(results, &match?({:ok, _result}, &1))

      assert stale_change_id in Enum.map(intake.proposed_changes, & &1.id)

      {:ok, persisted_changes} =
        with_unboxed_connection(fn ->
          ProposedChanges.get_many(
            bootstrap.session,
            Enum.map(intake.proposed_changes, & &1.id)
          )
        end)

      assert Enum.all?(persisted_changes, &(&1.status == "applied"))

      assert persisted_changes |> Enum.map(& &1.applied_operation_id) |> Enum.uniq() |> length() ==
               1
    after
      with_unboxed_connection(fn ->
        ConcurrencyCleanup.cleanup_work_run_verification_scope!(organization_slug)
        ConcurrencyCleanup.cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "waiver and acceptance serialize one result for a required check" do
    suffix = System.unique_integer([:positive])
    organization_slug = "waiver-accept-race-#{suffix}"
    owner_email = "waiver-accept-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, run, required_check, candidate, acceptance_operation, waiver_operation,
       waiver_attrs} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Waiver Accept Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Waiver Accept Race Workspace #{suffix}",
              workspace_slug: "waiver-accept-race-workspace-#{suffix}",
              owner_email: owner_email,
              owner_name: "Waiver Accept Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "waiver-accept-#{suffix}")

          {:ok, run_result} =
            create_concurrency_ready_run(bootstrap.session, [verification_check], suffix)

          {:ok, observation_result} =
            record_concurrency_observation(
              bootstrap.session,
              run_result.run,
              verification_check,
              "waiver-accept-#{suffix}"
            )

          {:ok, candidate} =
            create_concurrency_candidate(
              bootstrap.session,
              observation_result.run,
              verification_check,
              observation_result.observation,
              "waiver-accept-#{suffix}"
            )

          {:ok, acceptance_operation} =
            Operations.start_operation(bootstrap.session, :evidence_accept,
              idempotency_key: "waiver-accept-race-accept-#{suffix}"
            )

          [required_check] = run_result.required_checks

          waiver_attrs = %{
            expected_execution_state: observation_result.run.execution_state,
            expected_verification_state: observation_result.run.verification_state,
            reason: "Concurrent governed exception.",
            policy_basis: "owner_exception"
          }

          {:ok, waiver_operation} =
            Operations.start_command(
              bootstrap.session,
              :verification_waive,
              "waiver-accept-race-waive-#{suffix}",
              waiver_attrs
              |> Map.put(:run_id, observation_result.run.id)
              |> Map.put(:run_required_check_id, required_check.id)
            )

          {bootstrap, observation_result.run, required_check, candidate, acceptance_operation,
           waiver_operation, waiver_attrs}
        end)

      results =
        run_concurrently([
          fn ->
            Verification.accept_evidence_candidate(
              bootstrap.session,
              acceptance_operation,
              candidate,
              %{
                title: "Concurrent accepted evidence",
                body: "Acceptance competes with a governed waiver.",
                result: "passed",
                acceptance_policy_basis: "owner_acceptance"
              }
            )
          end,
          fn ->
            Verification.waive_required_check(
              bootstrap.session,
              waiver_operation,
              run,
              required_check,
              waiver_attrs
            )
          end
        ])

      assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _result}, &1))

      assert [loser] = Enum.reject(results, &match?({:ok, _result}, &1))

      assert match?(
               {:error, {:verification_result_slot_conflict, _, _}},
               loser
             ) or
               match?(
                 {:error, {:run_required_check_not_pending, _, _}},
                 loser
               )

      assert winner.verification_result.result in ["passed", "waived"]

      assert 1 ==
               with_unboxed_connection(fn ->
                 run_verification_result_count(
                   run.id,
                   required_check.verification_check_id
                 )
               end)
    after
      with_unboxed_connection(fn ->
        ConcurrencyCleanup.cleanup_work_run_verification_scope!(organization_slug)
        ConcurrencyCleanup.cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end
end
