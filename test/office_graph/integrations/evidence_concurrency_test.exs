defmodule OfficeGraph.Integrations.EvidenceConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  test "evidence candidate creation is idempotent under operation replay races" do
    suffix = System.unique_integer([:positive])
    organization_slug = "evidence-candidate-create-race-#{suffix}"
    workspace_slug = "evidence-candidate-create-race-workspace-#{suffix}"
    owner_email = "evidence-candidate-create-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, candidate_operation, attrs} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Evidence Candidate Create Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Evidence Candidate Create Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Evidence Candidate Create Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "candidate-#{suffix}")

          {:ok, run_result} =
            create_concurrency_ready_run(bootstrap.session, [verification_check], suffix)

          {:ok, observation_result} =
            record_concurrency_observation(
              bootstrap.session,
              run_result.run,
              verification_check,
              "candidate-#{suffix}"
            )

          {:ok, candidate_operation} =
            Operations.start_operation(bootstrap.session, :evidence_candidate_create,
              idempotency_key: "evidence-candidate-create-race-#{suffix}"
            )

          install_evidence_candidate_insert_barrier!(candidate_operation.id)

          attrs = %{
            work_run_id: run_result.run.id,
            verification_check_id: verification_check.id,
            execution_observation_id: observation_result.observation.id,
            claim: "Concurrent evidence candidate #{suffix}.",
            source_kind: "provider_check",
            source_identity: "provider:evidence-candidate-create-race-#{suffix}",
            freshness_state: "fresh",
            trust_basis: "signed_provider_payload",
            sensitivity: "internal"
          }

          {bootstrap, candidate_operation, attrs}
        end)

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              Verification.create_evidence_candidate(
                bootstrap.session,
                candidate_operation,
                attrs
              )
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.id == second.id

      assert 1 =
               with_unboxed_connection(fn ->
                 evidence_candidate_creation_count(candidate_operation.id)
               end)
    after
      with_unboxed_connection(fn ->
        drop_evidence_candidate_insert_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "evidence acceptance replays after concurrent candidate locking" do
    suffix = System.unique_integer([:positive])
    organization_slug = "evidence-accept-race-#{suffix}"
    workspace_slug = "evidence-accept-race-workspace-#{suffix}"
    owner_email = "evidence-accept-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, candidate, acceptance_operation} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Evidence Accept Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Evidence Accept Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Evidence Accept Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "accept-#{suffix}")

          {:ok, run_result} =
            create_concurrency_ready_run(bootstrap.session, [verification_check], suffix)

          {:ok, observation_result} =
            record_concurrency_observation(
              bootstrap.session,
              run_result.run,
              verification_check,
              "accept-#{suffix}"
            )

          {:ok, candidate} =
            create_concurrency_candidate(
              bootstrap.session,
              run_result.run,
              verification_check,
              observation_result.observation,
              "accept-#{suffix}"
            )

          {:ok, acceptance_operation} =
            Operations.start_operation(bootstrap.session, :evidence_accept,
              idempotency_key: "evidence-accept-race-#{suffix}"
            )

          install_evidence_item_insert_barrier!(candidate.id)

          {bootstrap, candidate, acceptance_operation}
        end)

      results =
        1..2
        |> Enum.map(fn _index ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              Verification.accept_evidence_candidate(
                bootstrap.session,
                acceptance_operation,
                candidate,
                %{
                  title: "Concurrent accepted evidence",
                  body: "Concurrent accepted evidence body.",
                  result: "passed",
                  acceptance_policy_basis: "owner_acceptance"
                }
              )
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.evidence_item.id == second.evidence_item.id
      assert first.verification_result.id == second.verification_result.id

      assert {1, 1} =
               with_unboxed_connection(fn ->
                 evidence_acceptance_counts(candidate.id)
               end)
    after
      with_unboxed_connection(fn ->
        drop_evidence_item_insert_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "different candidates concurrently compete for one run verification result slot" do
    suffix = System.unique_integer([:positive])
    organization_slug = "evidence-result-slot-race-#{suffix}"
    workspace_slug = "evidence-result-slot-race-workspace-#{suffix}"
    owner_email = "evidence-result-slot-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, run, verification_check, candidates} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Evidence Result Slot Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Evidence Result Slot Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Evidence Result Slot Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "result-slot-#{suffix}")

          {:ok, run_result} =
            create_concurrency_ready_run(bootstrap.session, [verification_check], suffix)

          candidates =
            Enum.map(1..2, fn index ->
              key = "result-slot-#{suffix}-#{index}"

              {:ok, observation_result} =
                record_concurrency_observation(
                  bootstrap.session,
                  run_result.run,
                  verification_check,
                  key
                )

              {:ok, candidate} =
                create_concurrency_candidate(
                  bootstrap.session,
                  run_result.run,
                  verification_check,
                  observation_result.observation,
                  key
                )

              candidate
            end)

          {bootstrap, run_result.run, verification_check, candidates}
        end)

      results =
        candidates
        |> Enum.with_index(1)
        |> Enum.map(fn {candidate, index} ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              {:ok, operation} =
                Operations.start_operation(bootstrap.session, :evidence_accept,
                  idempotency_key: "evidence-result-slot-race-#{suffix}-#{index}"
                )

              Verification.accept_evidence_candidate(
                bootstrap.session,
                operation,
                candidate,
                %{
                  title: "Concurrent result slot evidence #{index}",
                  body: "Only one candidate may occupy the run verification result slot.",
                  result: "passed",
                  acceptance_policy_basis: "owner_acceptance"
                }
              )
            end)
          end)
        end)
        |> Task.await_many(15_000)

      assert [_accepted] = for({:ok, result} <- results, do: result)

      assert [{run.id, verification_check.id}] ==
               for(
                 {:error, {:verification_result_slot_conflict, run_id, verification_check_id}} <-
                   results,
                 do: {run_id, verification_check_id}
               )

      assert 1 ==
               with_unboxed_connection(fn ->
                 run_verification_result_count(run.id, verification_check.id)
               end)
    after
      with_unboxed_connection(fn ->
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "evidence acceptance replays one operation across different candidate locks" do
    suffix = System.unique_integer([:positive])
    organization_slug = "evidence-accept-operation-race-#{suffix}"
    workspace_slug = "evidence-accept-operation-race-workspace-#{suffix}"
    owner_email = "evidence-accept-operation-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, first_candidate, second_candidate, acceptance_operation} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Evidence Accept Operation Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Evidence Accept Operation Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Evidence Accept Operation Race Owner"
            )

          {:ok, first_check} =
            create_concurrency_verification_check(bootstrap.session, "accept-first-#{suffix}")

          {:ok, second_check} =
            create_concurrency_verification_check(bootstrap.session, "accept-second-#{suffix}")

          {:ok, run_result} =
            create_concurrency_ready_run(bootstrap.session, [first_check, second_check], suffix)

          {:ok, first_observation} =
            record_concurrency_observation(
              bootstrap.session,
              run_result.run,
              first_check,
              "accept-first-#{suffix}"
            )

          {:ok, second_observation} =
            record_concurrency_observation(
              bootstrap.session,
              run_result.run,
              second_check,
              "accept-second-#{suffix}"
            )

          {:ok, first_candidate} =
            create_concurrency_candidate(
              bootstrap.session,
              run_result.run,
              first_check,
              first_observation.observation,
              "accept-first-#{suffix}"
            )

          {:ok, second_candidate} =
            create_concurrency_candidate(
              bootstrap.session,
              run_result.run,
              second_check,
              second_observation.observation,
              "accept-second-#{suffix}"
            )

          {:ok, acceptance_operation} =
            Operations.start_operation(bootstrap.session, :evidence_accept,
              idempotency_key: "evidence-accept-operation-race-#{suffix}"
            )

          install_evidence_item_operation_insert_barrier!(acceptance_operation.id)

          {bootstrap, first_candidate, second_candidate, acceptance_operation}
        end)

      results =
        [first_candidate, second_candidate]
        |> Enum.with_index(1)
        |> Enum.map(fn {candidate, index} ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              Verification.accept_evidence_candidate(
                bootstrap.session,
                acceptance_operation,
                candidate,
                %{
                  title: "Concurrent operation accepted evidence #{index}",
                  body: "Concurrent operation accepted evidence body #{index}.",
                  result: "passed",
                  acceptance_policy_basis: "owner_acceptance"
                }
              )
            end)
          end)
        end)
        |> Task.await_many(10_000)

      successes = for {:ok, accepted} <- results, do: accepted
      conflicts = for {:error, {:evidence_acceptance_operation_conflict, id}} <- results, do: id

      assert [accepted] = successes
      assert [accepted.evidence_item.id] == conflicts

      assert {1, 1} =
               with_unboxed_connection(fn ->
                 evidence_acceptance_operation_counts(acceptance_operation.id)
               end)
    after
      with_unboxed_connection(fn ->
        drop_evidence_item_operation_insert_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "standalone observation recording serializes source idempotency replays" do
    suffix = System.unique_integer([:positive])
    shared_source_identity = "provider:standalone-observation-race-#{suffix}"
    shared_observation_key = "standalone-observation-race-#{suffix}"

    try do
      {bootstrap, first_check, second_check, first_run, second_run, first_operation,
       second_operation} =
        with_unboxed_connection(fn ->
          cleanup_work_run_verification_scope!("office-graph")
          cleanup_bootstrap_scope!("office-graph", "owner@office-graph.local")

          {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

          {:ok, first_check} =
            create_concurrency_verification_check(
              bootstrap.session,
              "standalone-observation-race-first-#{suffix}"
            )

          {:ok, second_check} =
            create_concurrency_verification_check(
              bootstrap.session,
              "standalone-observation-race-second-#{suffix}"
            )

          {:ok, first_run} =
            create_concurrency_ready_run(
              bootstrap.session,
              [first_check],
              "standalone-observation-race-first-#{suffix}"
            )

          {:ok, second_run} =
            create_concurrency_ready_run(
              bootstrap.session,
              [second_check],
              "standalone-observation-race-second-#{suffix}"
            )

          {:ok, first_operation} =
            Operations.start_operation(bootstrap.session, :execution_observation_record,
              idempotency_key: "standalone-observation-race-first-#{suffix}"
            )

          {:ok, second_operation} =
            Operations.start_operation(bootstrap.session, :execution_observation_record,
              idempotency_key: "standalone-observation-race-second-#{suffix}"
            )

          install_execution_observation_insert_barrier!(shared_observation_key)

          {bootstrap, first_check, second_check, first_run, second_run, first_operation,
           second_operation}
        end)

      first_attrs =
        standalone_observation_attrs(first_check, shared_source_identity, shared_observation_key)

      second_attrs =
        standalone_observation_attrs(second_check, shared_source_identity, shared_observation_key)

      results =
        [
          {first_operation, first_run.run, first_attrs},
          {second_operation, second_run.run, second_attrs}
        ]
        |> Enum.map(fn {operation, run, attrs} ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              Runs.record_observation(bootstrap.session, operation, run, attrs)
            end)
          end)
        end)
        |> Task.await_many(15_000)

      assert [successful] = for({:ok, result} <- results, do: result)

      assert [successful.observation.id] ==
               for({:error, {:observation_idempotency_conflict, id}} <- results, do: id)

      assert 1 ==
               with_unboxed_connection(fn ->
                 observation_source_key_count(shared_source_identity, shared_observation_key)
               end)
    after
      with_unboxed_connection(fn ->
        drop_execution_observation_insert_barrier!()
        cleanup_work_run_verification_scope!("office-graph")
        cleanup_bootstrap_scope!("office-graph", "owner@office-graph.local")
      end)
    end
  end

  test "runless evidence acceptance follows completion lock order under direct completion races" do
    suffix = System.unique_integer([:positive])
    organization_slug = "runless-completion-race-#{suffix}"
    workspace_slug = "runless-completion-race-workspace-#{suffix}"
    owner_email = "runless-completion-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, verification_check, candidate, acceptance_operation, completion_operation} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Runless Completion Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Runless Completion Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Runless Completion Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(
              bootstrap.session,
              "runless-completion-race-#{suffix}"
            )

          {:ok, candidate_operation} =
            Operations.start_operation(bootstrap.session, :evidence_candidate_create,
              idempotency_key: "runless-completion-race-candidate-#{suffix}"
            )

          {:ok, candidate} =
            Verification.create_evidence_candidate(bootstrap.session, candidate_operation, %{
              verification_check_id: verification_check.id,
              claim: "Runless candidate races with direct completion.",
              source_kind: "human_note",
              source_identity: "manual:runless-completion-race-#{suffix}",
              freshness_state: "fresh",
              trust_basis: "owner_attested",
              sensitivity: "internal"
            })

          {:ok, acceptance_operation} =
            Operations.start_operation(bootstrap.session, :evidence_accept,
              idempotency_key: "runless-completion-race-accept-#{suffix}"
            )

          {:ok, completion_operation} =
            Operations.start_operation(bootstrap.session, :verification_complete,
              idempotency_key: "runless-completion-race-complete-#{suffix}"
            )

          install_verification_result_insert_barrier!(verification_check.id)

          {bootstrap, verification_check, candidate, acceptance_operation, completion_operation}
        end)

      results =
        [
          fn ->
            Verification.accept_evidence_candidate(
              bootstrap.session,
              acceptance_operation,
              candidate,
              %{
                title: "Runless race evidence",
                body: "Runless candidate evidence accepted in a race.",
                result: "passed",
                acceptance_policy_basis: "owner_acceptance"
              }
            )
          end,
          fn ->
            Verification.complete_with_evidence(
              bootstrap.session,
              completion_operation,
              verification_check,
              %{
                title: "Direct race evidence",
                body: "Direct completion evidence accepted in a race.",
                artifact_uri: "https://example.test/runless-completion-race/#{suffix}"
              }
            )
          end
        ]
        |> Enum.map(fn fun ->
          Task.async(fn ->
            with_unboxed_connection(fun)
          end)
        end)
        |> Task.await_many(15_000)

      successes = for {:ok, result} <- results, do: result
      invalid_statuses = for {:error, {:invalid_verification_check_status, id}} <- results, do: id

      assert [_success] = successes
      assert [verification_check.id] == invalid_statuses

      assert 1 ==
               with_unboxed_connection(fn ->
                 no_run_verification_result_count(verification_check.id)
               end)
    after
      with_unboxed_connection(fn ->
        drop_verification_result_insert_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "concurrent evidence acceptance verifies run once all required checks are satisfied" do
    suffix = System.unique_integer([:positive])
    organization_slug = "run-verification-race-#{suffix}"
    workspace_slug = "run-verification-race-workspace-#{suffix}"
    owner_email = "run-verification-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, run_id, first_candidate, second_candidate} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Run Verification Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Run Verification Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Run Verification Race Owner"
            )

          {:ok, first_check} =
            create_concurrency_verification_check(bootstrap.session, "first-#{suffix}")

          {:ok, second_check} =
            create_concurrency_verification_check(bootstrap.session, "second-#{suffix}")

          {:ok, run_result} =
            create_concurrency_ready_run(bootstrap.session, [first_check, second_check], suffix)

          {:ok, first_observation} =
            record_concurrency_observation(
              bootstrap.session,
              run_result.run,
              first_check,
              "first-#{suffix}"
            )

          {:ok, second_observation} =
            record_concurrency_observation(
              bootstrap.session,
              run_result.run,
              second_check,
              "second-#{suffix}"
            )

          {:ok, first_candidate} =
            create_concurrency_candidate(
              bootstrap.session,
              run_result.run,
              first_check,
              first_observation.observation,
              "first-#{suffix}"
            )

          {:ok, second_candidate} =
            create_concurrency_candidate(
              bootstrap.session,
              run_result.run,
              second_check,
              second_observation.observation,
              "second-#{suffix}"
            )

          install_run_required_check_update_barrier!(run_result.run.id)

          {bootstrap, run_result.run.id, first_candidate, second_candidate}
        end)

      results =
        [first_candidate, second_candidate]
        |> Enum.with_index(1)
        |> Enum.map(fn {candidate, index} ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              {:ok, operation} =
                Operations.start_operation(bootstrap.session, :evidence_accept,
                  idempotency_key: "run-verification-race-accept-#{suffix}-#{index}"
                )

              Verification.accept_evidence_candidate(bootstrap.session, operation, candidate, %{
                title: "Concurrent evidence #{index}",
                body: "Concurrent evidence body #{index}.",
                result: "passed",
                acceptance_policy_basis: "owner_acceptance"
              })
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, _first_accepted}, {:ok, _second_accepted}] = results

      with_unboxed_connection(fn ->
        {:ok, summary} = Runs.get_summary(bootstrap.session, run_id)

        assert Enum.all?(summary.required_checks, &(&1.state == "satisfied"))
        assert summary.run.aggregate_state == "verified"
        assert summary.run.verification_state == "verified"
      end)
    after
      with_unboxed_connection(fn ->
        drop_run_required_check_update_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "manual intake proposed change creation is idempotent under absent-set races" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    source_identity = "manual:proposed-change-race-#{suffix}"
    replay_identity = "paste:proposed-change-race-#{suffix}"
    body = "Task: verify concurrent proposed change creation #{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    try do
      {operation, normalized_event} =
        with_unboxed_connection(fn ->
          insert_minimal_session_scope!(
            organization_id,
            workspace_id,
            principal_id,
            session_id,
            suffix
          )

          {:ok, operation} =
            Operations.start_operation(session_context, :manual_intake_submit,
              correlation_id: "proposed-change-race-#{suffix}"
            )

          normalized_event =
            insert_accepted_intake_event_without_proposed_changes!(
              session_context,
              operation,
              source_identity,
              replay_identity,
              body
            )

          install_proposed_change_insert_barrier!(normalized_event.id)

          {operation, normalized_event}
        end)

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              capture_create_for_manual_intake(
                session_context,
                operation,
                normalized_event,
                body
              )
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert length(first) == 4
      assert length(second) == 4
      assert Enum.map(first, & &1.id) |> Enum.sort() == Enum.map(second, & &1.id) |> Enum.sort()
      assert with_unboxed_connection(fn -> proposed_change_count(normalized_event.id) end) == 4
    after
      with_unboxed_connection(fn ->
        drop_proposed_change_insert_barrier!()
        cleanup_committed_scope!(organization_id, principal_id, source_identity)
      end)
    end
  end
end
