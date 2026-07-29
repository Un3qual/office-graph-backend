defmodule OfficeGraph.Projections.OperatorRunProjectionTest do
  use OfficeGraph.TestSupport.OperatorProjectionSupport

  test "operator run state moves from missing evidence to verified" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    assert {:ok, initial_state} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert initial_state.status == "awaiting_execution"
    assert is_binary(initial_state.source_watermark)

    assert initial_state.allowed_next_actions == [
             "record_execution_observation",
             "waive_verification_check"
           ]

    assert [record_observation, waive_check] = initial_state.command_affordances
    assert record_observation.identity == "record_execution_observation"
    assert record_observation.state == "enabled"
    assert record_observation.reason_codes == []
    assert record_observation.blocker_reasons == []
    assert record_observation.safe_explanation == "Record execution observations for this run."

    assert record_observation.required_fields == [
             "run_id",
             "observation_source_kind",
             "observation_source_identity",
             "observation_idempotency_key",
             "observed_status",
             "normalized_status",
             "freshness_state",
             "trust_basis",
             "verification_check_id",
             "source_graph_item_id",
             "observation_rationale"
           ]

    assert record_observation.input_defaults == [
             %{field: "run_id", value: run_result.run.id, values: []}
           ]

    assert %{type: "work_run", id: run_result.run.id} in record_observation.target_ids

    assert %{type: "verification_check", id: verification_check.id} in record_observation.target_ids

    assert waive_check.identity == "waive_verification_check"
    assert waive_check.state == "enabled"

    assert initial_state.missing_evidence == [
             %{verification_check_id: verification_check.id, reason: "missing_accepted_evidence"}
           ]

    assert hd(initial_state.command_options.observation).source_graph_item_id ==
             verification_check.graph_item_id

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "operator-run-state"
      )

    assert {:ok, awaiting_candidate} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert awaiting_candidate.status == "awaiting_evidence"

    assert awaiting_candidate.allowed_next_actions == [
             "create_evidence_candidate",
             "waive_verification_check"
           ]

    assert [create_candidate, waive_check] = awaiting_candidate.command_affordances
    assert waive_check.identity == "waive_verification_check"

    assert create_candidate.required_fields == [
             "work_run_id",
             "verification_check_id",
             "execution_observation_id",
             "claim",
             "source_kind",
             "source_identity",
             "freshness_state",
             "trust_basis",
             "sensitivity"
           ]

    assert create_candidate.input_defaults == [
             %{field: "work_run_id", value: run_result.run.id, values: []},
             %{field: "verification_check_id", value: nil, values: [verification_check.id]},
             %{
               field: "execution_observation_id",
               value: nil,
               values: [observation_result.observation.id]
             },
             %{field: "sensitivity", value: "internal", values: []}
           ]

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

    assert awaiting_evidence.allowed_next_actions == [
             "accept_evidence",
             "waive_verification_check"
           ]

    assert [accept_evidence, waive_check] = awaiting_evidence.command_affordances
    assert waive_check.identity == "waive_verification_check"
    assert accept_evidence.identity == "accept_evidence"
    assert accept_evidence.state == "enabled"
    assert accept_evidence.reason_codes == []
    assert accept_evidence.blocker_reasons == []

    assert accept_evidence.safe_explanation ==
             "Accept a candidate as evidence for a missing check."

    assert accept_evidence.required_fields == [
             "evidence_candidate_id",
             "title",
             "body",
             "result",
             "acceptance_policy_basis"
           ]

    assert %{type: "evidence_candidate", id: candidate.id} in accept_evidence.target_ids

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate, key: "operator-run-state", result: "passed")

    assert {:ok, verified_state} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    assert verified_state.status == "verified"
    assert verified_state.allowed_next_actions == []
    assert verified_state.command_affordances == []
    assert verified_state.missing_evidence == []
    assert verified_state.child_summary.evidence_items == 1
    assert verified_state.child_summary.verification_results == 1
  end

  test "operator run state advertises GraphQL observation and waiver commands" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    assert {:ok, run_state} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert run_state.allowed_next_actions == [
             "record_execution_observation",
             "waive_verification_check"
           ]

    assert [record_observation, waive_check] = run_state.command_affordances
    assert record_observation.identity == "record_execution_observation"
    assert waive_check.identity == "waive_verification_check"

    assert waive_check.required_fields == [
             "run_id",
             "run_required_check_id",
             "expected_execution_state",
             "expected_verification_state",
             "reason",
             "policy_basis"
           ]

    assert waive_check.input_defaults == [
             %{field: "run_id", value: run_result.run.id, values: []},
             %{
               field: "run_required_check_id",
               value: nil,
               values: Enum.map(run_result.required_checks, & &1.id)
             },
             %{
               field: "expected_execution_state",
               value: run_result.run.execution_state,
               values: []
             },
             %{
               field: "expected_verification_state",
               value: run_result.run.verification_state,
               values: []
             }
           ]
  end

  test "operator run command options preserve keyset pagination and exact summary counts" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, first_check} = create_required_verification_check(bootstrap.session)
    {:ok, second_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, [first_check, second_check])

    assert {:ok, run_state} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    assert run_state.command_option_summary.observation == 2
    assert run_state.command_option_summary.waiver == 2
    refute run_state.command_options_overflow

    assert {:ok, first_page} =
             Projections.operator_run_command_option_page(
               bootstrap.session,
               run_result.run.id,
               "observation",
               limit: 1,
               after_cursor: nil
             )

    assert [%{node: first_choice, cursor: cursor}] = first_page.edges
    assert first_choice.observation.run_id == run_result.run.id
    assert first_page.has_next_page?
    refute first_page.has_previous_page?

    assert {:ok, second_page} =
             Projections.operator_run_command_option_page(
               bootstrap.session,
               run_result.run.id,
               "observation",
               limit: 1,
               after_cursor: cursor
             )

    assert [%{node: second_choice}] = second_page.edges
    refute second_page.has_next_page?
    assert second_page.has_previous_page?
    refute second_choice.key == first_choice.key

    assert MapSet.new([
             first_choice.observation.verification_check_id,
             second_choice.observation.verification_check_id
           ]) == MapSet.new([first_check.id, second_check.id])

    activity_edges = collect_activity_edges(bootstrap.session, run_result.run.id)

    assert activity_edges
           |> Enum.filter(&(&1.node.kind == "missing_evidence"))
           |> MapSet.new(& &1.node.stable_id) ==
             MapSet.new([first_check.id, second_check.id])
  end

  test "operator run state source watermark changes when visible child state changes" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

    assert {:ok, initial_state} =
             Projections.operator_run_state(bootstrap.session, run_result.run.id)

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "run-watermark-observation"
      )

    assert {:ok, observed_state} =
             Projections.operator_run_state(bootstrap.session, observation_result.run.id)

    refute observed_state.source_watermark == initial_state.source_watermark

    {:ok, candidate} =
      create_evidence_candidate(
        bootstrap.session,
        observation_result.run,
        verification_check,
        observation_result.observation,
        key: "run-watermark-candidate"
      )

    {:ok, accepted} =
      accept_candidate(bootstrap.session, candidate,
        key: "run-watermark-candidate",
        result: "passed"
      )

    assert {:ok, accepted_state} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    refute accepted_state.source_watermark == observed_state.source_watermark
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

      assert awaiting_evidence.allowed_next_actions == [
               "create_evidence_candidate",
               "waive_verification_check"
             ]

      assert awaiting_evidence.command_options.evidence_acceptance == []

      refute Enum.any?(
               awaiting_evidence.command_affordances,
               &(%{type: "evidence_candidate", id: candidate.id} in &1.target_ids)
             )
    end
  end

  test "operator run state only defaults passed-acceptance-eligible observations" do
    for {key, observation_overrides} <- [
          {"failed-observation", [normalized_status: "failed", observed_status: "failed"]},
          {"stale-observation", [freshness_state: "stale"]},
          {"untrusted-observation", [trust_basis: "unauthenticated"]}
        ] do
      {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
      {:ok, verification_check} = create_required_verification_check(bootstrap.session)
      {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)

      {:ok, observation_result} =
        record_observation(
          bootstrap.session,
          run_result.run,
          verification_check,
          Keyword.put(observation_overrides, :key, key)
        )

      assert {:ok, run_state} =
               Projections.operator_run_state(bootstrap.session, observation_result.run.id)

      create_candidate =
        Enum.find(run_state.command_affordances, &(&1.identity == "create_evidence_candidate"))

      if run_state.status == "failed" do
        assert is_nil(create_candidate)
        assert run_state.status == "failed"
      else
        assert is_nil(create_candidate)

        assert Enum.any?(
                 run_state.command_affordances,
                 &(&1.identity == "record_execution_observation" and &1.state == "enabled")
               )
      end
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

    assert {:ok, remaining_execution} =
             Projections.operator_run_state(bootstrap.session, accepted.work_run.id)

    assert remaining_execution.status == "awaiting_evidence"

    assert remaining_execution.allowed_next_actions == [
             "record_execution_observation",
             "waive_verification_check"
           ]

    record_observation =
      Enum.find(
        remaining_execution.command_affordances,
        &(&1.identity == "record_execution_observation")
      )

    assert record_observation.state == "enabled"
    assert %{type: "verification_check", id: second_check.id} in record_observation.target_ids
    refute %{type: "verification_check", id: first_check.id} in record_observation.target_ids

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

    assert waiting_state.allowed_next_actions == [
             "accept_evidence",
             "waive_verification_check"
           ]

    assert Enum.any?(
             waiting_state.command_options.evidence_acceptance,
             &(&1.evidence_candidate_id == second_candidate.id and
                 &1.verification_check_id == second_check.id)
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
             %{verification_check_id: verification_check.id, reason: "failed_check"}
           ]

    assert failed_state.child_summary.verification_results == 1
    assert accepted.verification_result.result == "failed"
  end

  test "operator run state command affordances require command capabilities" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, run_result} = create_ready_run(bootstrap.session, verification_check)
    read_only_session = create_session_with_capabilities!(bootstrap, ["skeleton.read"])

    assert {:ok, initial_state} =
             Projections.operator_run_state(read_only_session, run_result.run.id)

    assert initial_state.status == "awaiting_execution"
    assert initial_state.allowed_next_actions == []
    assert [record_observation] = initial_state.command_affordances
    assert record_observation.identity == "record_execution_observation"
    assert record_observation.state == "hidden"
    assert record_observation.reason_codes == ["policy_restricted"]
    assert record_observation.blocker_reasons == ["policy_restricted"]
    assert record_observation.target_ids == []
    refute inspect(record_observation) =~ "execution_observation.record"

    {:ok, observation_result} =
      record_observation(bootstrap.session, run_result.run, verification_check,
        key: "read-only-run-state"
      )

    assert {:ok, awaiting_evidence} =
             Projections.operator_run_state(read_only_session, run_result.run.id)

    assert awaiting_evidence.status == "awaiting_evidence"
    assert awaiting_evidence.allowed_next_actions == []
    assert [create_candidate] = awaiting_evidence.command_affordances
    assert create_candidate.identity == "create_evidence_candidate"
    assert create_candidate.state == "hidden"
    assert create_candidate.reason_codes == ["policy_restricted"]
    assert create_candidate.blocker_reasons == ["policy_restricted"]
    assert create_candidate.target_ids == []
    refute inspect(create_candidate) =~ "evidence_candidate.create"

    {:ok, _candidate} =
      create_evidence_candidate(
        bootstrap.session,
        run_result.run,
        verification_check,
        observation_result.observation,
        key: "read-only-run-state"
      )

    assert {:ok, awaiting_acceptance} =
             Projections.operator_run_state(read_only_session, run_result.run.id)

    assert awaiting_acceptance.status == "awaiting_evidence_acceptance"
    assert awaiting_acceptance.allowed_next_actions == []
    assert [accept_evidence] = awaiting_acceptance.command_affordances
    assert accept_evidence.identity == "accept_evidence"
    assert accept_evidence.state == "hidden"
    assert accept_evidence.reason_codes == ["policy_restricted"]
    assert accept_evidence.blocker_reasons == ["policy_restricted"]
    assert accept_evidence.target_ids == []
    refute inspect(accept_evidence) =~ "evidence.accept"
  end

  test "run state, activity, and option pages reject cross-scope and unauthorized reads" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, local_check} = create_required_verification_check(bootstrap.session)
    {:ok, local_run} = create_ready_run(bootstrap.session, local_check)

    suffix = System.unique_integer([:positive])

    {:ok, foreign_scope} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Foreign projection workspace #{suffix}",
        workspace_slug: "foreign-projection-workspace-#{suffix}",
        initiative_name: "Foreign projection initiative #{suffix}",
        initiative_slug: "foreign-projection-initiative-#{suffix}"
      )

    {:ok, foreign_check} = create_required_verification_check(foreign_scope.session)
    {:ok, foreign_run} = create_ready_run(foreign_scope.session, foreign_check)

    assert {:error, :forbidden} =
             Projections.operator_run_state(bootstrap.session, foreign_run.run.id)

    assert {:error, :forbidden} =
             Projections.operator_run_activity_page(bootstrap.session, foreign_run.run.id,
               limit: 20,
               after_cursor: nil
             )

    assert {:error, :forbidden} =
             Projections.operator_run_command_option_page(
               bootstrap.session,
               foreign_run.run.id,
               "observation",
               limit: 20,
               after_cursor: nil
             )

    denied_session = create_session_with_capabilities!(bootstrap, [])

    assert {:error, :forbidden} =
             Projections.operator_run_state(denied_session, local_run.run.id)

    assert {:error, :forbidden} =
             Projections.operator_run_activity_page(denied_session, local_run.run.id,
               limit: 20,
               after_cursor: nil
             )

    assert {:error, :forbidden} =
             Projections.operator_run_command_option_page(
               denied_session,
               local_run.run.id,
               "observation",
               limit: 20,
               after_cursor: nil
             )
  end

  defp collect_activity_edges(session, run_id, cursor \\ nil, edges \\ []) do
    assert {:ok, page} =
             Projections.operator_run_activity_page(session, run_id,
               limit: 1,
               after_cursor: cursor
             )

    edges = edges ++ page.edges

    if page.has_next_page? do
      collect_activity_edges(session, run_id, List.last(page.edges).cursor, edges)
    else
      edges
    end
  end
end
