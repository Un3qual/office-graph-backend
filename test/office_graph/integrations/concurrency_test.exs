defmodule OfficeGraph.Integrations.ConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.ProposedChanges

  alias OfficeGraph.{
    Foundation,
    Integrations,
    Operations,
    Repo,
    Runs,
    Tenancy,
    Verification
  }

  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkPackets

  test "manual intake retries recover proposed changes after proposed-change creation fails" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    source_identity = "manual:atomicity-#{suffix}"
    replay_identity = "paste:atomicity-#{suffix}"
    body = "Task: trigger proposed change failure #{suffix} with 'quote' and $$tag$$"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    attrs = %{
      source_identity: source_identity,
      replay_identity: replay_identity,
      body: body
    }

    try do
      with_unboxed_connection(fn ->
        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )

        install_proposed_change_failure_trigger!(body)

        {:ok, operation} =
          Operations.start_operation(session_context, :manual_intake_submit,
            correlation_id: "atomicity-#{suffix}"
          )

        assert {:error, _error} = capture_submit(session_context, operation, attrs)
        assert accepted_event_count(organization_id, source_identity, replay_identity) == 0

        drop_proposed_change_failure_trigger!()

        assert {:ok, retry} = Integrations.submit_manual_intake(session_context, operation, attrs)
        assert retry.duplicate? == false
        assert retry.normalized_event.outcome == "accepted"
        assert length(retry.proposed_changes) == 4
      end)
    after
      with_unboxed_connection(fn ->
        drop_proposed_change_failure_trigger!()
        cleanup_committed_scope!(organization_id, principal_id, source_identity)
      end)
    end
  end

  test "manual intake rejects operation contexts that do not match the caller" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    other_principal_id = Ecto.UUID.generate()
    other_session_id = Ecto.UUID.generate()
    source_identity = "manual:operation-context-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    other_session_context = %SessionContext{
      principal_id: other_principal_id,
      session_id: other_session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    try do
      with_unboxed_connection(fn ->
        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )

        insert_additional_session_in_scope!(
          organization_id,
          workspace_id,
          other_principal_id,
          other_session_id,
          suffix
        )

        {:ok, wrong_action_operation} =
          Operations.start_operation(session_context, :proposed_change_apply,
            correlation_id: "operation-context-wrong-action-#{suffix}"
          )

        wrong_action_attrs = %{
          source_identity: source_identity,
          replay_identity: "paste:wrong-action-#{suffix}",
          body: "Task: reject non-manual operation context #{suffix}"
        }

        assert {:error, :forbidden} =
                 Integrations.submit_manual_intake(
                   session_context,
                   wrong_action_operation,
                   wrong_action_attrs
                 )

        {:ok, wrong_session_operation} =
          Operations.start_operation(other_session_context, :manual_intake_submit,
            correlation_id: "operation-context-wrong-session-#{suffix}"
          )

        wrong_session_attrs = %{
          source_identity: source_identity,
          replay_identity: "paste:wrong-session-#{suffix}",
          body: "Task: reject another session operation context #{suffix}"
        }

        assert {:error, :forbidden} =
                 Integrations.submit_manual_intake(
                   session_context,
                   wrong_session_operation,
                   wrong_session_attrs
                 )

        assert intake_record_count(organization_id, source_identity) == 0
      end)
    after
      with_unboxed_connection(fn ->
        cleanup_committed_scope!(
          organization_id,
          [principal_id, other_principal_id],
          source_identity
        )
      end)
    end
  end

  test "command manual-intake replay works with only intake capability" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    source_identity = "manual:command-limited-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    attrs = %{
      source_identity: source_identity,
      replay_identity: "paste:command-limited-#{suffix}",
      body: "Limited command replay #{suffix}"
    }

    try do
      with_unboxed_connection(fn ->
        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )

        {:ok, operation} =
          Operations.start_command(
            session_context,
            :manual_intake_submit,
            "command-limited-#{suffix}",
            attrs
          )

        assert {:ok, first} =
                 Integrations.submit_manual_intake(session_context, operation, attrs)

        assert {:ok, replay} =
                 Integrations.submit_manual_intake(session_context, operation, attrs)

        assert replay.normalized_event.id == first.normalized_event.id

        assert Enum.map(replay.proposed_changes, & &1.id) ==
                 Enum.map(first.proposed_changes, & &1.id)
      end)
    after
      with_unboxed_connection(fn ->
        cleanup_committed_scope!(organization_id, principal_id, source_identity)
      end)
    end
  end

  test "command manual-intake serializes same-operation replay before persistence" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    source_identity = "manual:command-race-#{suffix}"
    body = "Command replay race #{suffix}"
    lock_key = :erlang.phash2(source_identity, 2_000_000_000)

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    attrs = %{
      source_identity: source_identity,
      replay_identity: "paste:command-race-#{suffix}",
      body: body
    }

    try do
      {blocked_count, results} =
        with_unboxed_connection(fn ->
          insert_minimal_session_scope!(
            organization_id,
            workspace_id,
            principal_id,
            session_id,
            suffix
          )

          _source_id = insert_external_source!(source_identity)
          install_raw_archive_body_wait!(body, lock_key)
          Repo.query!("SELECT pg_advisory_lock(97001, $1)", [lock_key])

          {:ok, operation} =
            Operations.start_command(
              session_context,
              :manual_intake_submit,
              "command-race-#{suffix}",
              attrs
            )

          tasks =
            Enum.map(1..2, fn _attempt ->
              Task.async(fn ->
                with_unboxed_connection(fn ->
                  Integrations.submit_manual_intake(session_context, operation, attrs)
                end)
              end)
            end)

          wait_for_blocked_raw_archive!(lock_key)
          Process.sleep(100)
          blocked_count = blocked_raw_archive_count(lock_key)

          Repo.query!("SELECT pg_advisory_unlock(97001, $1)", [lock_key])
          {blocked_count, Task.await_many(tasks, 10_000)}
        end)

      assert [{:ok, first}, {:ok, replay}] = results
      assert blocked_count == 1
      assert replay.normalized_event.id == first.normalized_event.id
    after
      with_unboxed_connection(fn ->
        Repo.query!("SELECT pg_advisory_unlock(97001, $1)", [lock_key])
        drop_raw_archive_body_wait!()
        cleanup_committed_scope!(organization_id, principal_id, source_identity)
      end)
    end
  end

  test "first manual intakes sharing a new source survive the source creation race" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    source_identity = "manual:source-race-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    try do
      with_unboxed_connection(fn ->
        install_source_insert_barrier!()

        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )
      end)

      results =
        ["first", "second"]
        |> Enum.map(fn replay_identity ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              submit_manual_intake(session_context, source_identity, replay_identity)
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [
               {:ok, %{duplicate?: false, normalized_event: %{outcome: "accepted"}}},
               {:ok, %{duplicate?: false, normalized_event: %{outcome: "accepted"}}}
             ] = results

      source_ids =
        results
        |> Enum.map(fn {:ok, intake} -> intake.raw_archive.source_id end)
        |> Enum.uniq()

      assert length(source_ids) == 1
    after
      with_unboxed_connection(fn ->
        cleanup_committed_scope!(organization_id, principal_id, source_identity)
        drop_source_insert_barrier!()
      end)
    end
  end

  test "concurrent replay content conflicts from unique fallback return the accepted event id" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    source_identity = "manual:replay-conflict-race-#{suffix}"
    replay_identity = "paste:replay-conflict-race-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    blocked_body = "Task: blocked replay conflict loser #{suffix}"
    accepted_body = "Task: accepted replay conflict winner #{suffix}"
    lock_key = :erlang.phash2(source_identity, 2_000_000_000)

    try do
      result =
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
              correlation_id: "replay-conflict-blocked-loser-#{suffix}"
            )

          source_id = insert_external_source!(source_identity)
          install_raw_archive_body_wait!(blocked_body, lock_key)
          Repo.query!("SELECT pg_advisory_lock(97001, $1)", [lock_key])

          task =
            Task.async(fn ->
              with_unboxed_connection(fn ->
                capture_submit(session_context, operation, %{
                  source_identity: source_identity,
                  replay_identity: replay_identity,
                  body: blocked_body
                })
              end)
            end)

          wait_for_blocked_raw_archive!(lock_key)

          accepted =
            insert_accepted_intake_event_for_source!(
              session_context,
              operation,
              source_id,
              source_identity,
              replay_identity,
              accepted_body
            )

          Repo.query!("SELECT pg_advisory_unlock(97001, $1)", [lock_key])

          {Task.await(task, 10_000), accepted}
        end)

      {loser_result, accepted} = result
      accepted_event_id = accepted.id

      assert {:error, {:manual_intake_replay_conflict, ^accepted_event_id}} = loser_result

      assert with_unboxed_connection(fn ->
               accepted_event_count(organization_id, source_identity, replay_identity)
             end) == 1
    after
      with_unboxed_connection(fn ->
        Repo.query!("SELECT pg_advisory_unlock(97001, $1)", [lock_key])
        drop_raw_archive_body_wait!()
        cleanup_committed_scope!(organization_id, principal_id, source_identity)
      end)
    end
  end

  test "local tenancy bootstrap is idempotent under first-scope races" do
    suffix = System.unique_integer([:positive])
    organization_slug = "tenant-race-#{suffix}"
    workspace_slug = "tenant-race-workspace-#{suffix}"
    initiative_slug = "tenant-race-initiative-#{suffix}"

    attrs = [
      organization_name: "Tenant Race #{suffix}",
      organization_slug: organization_slug,
      workspace_name: "Tenant Race Workspace #{suffix}",
      workspace_slug: workspace_slug,
      initiative_name: "Tenant Race Initiative #{suffix}",
      initiative_slug: initiative_slug
    ]

    try do
      with_unboxed_connection(fn ->
        install_tenancy_insert_barrier!()
      end)

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              capture_ensure_local_scope(attrs)
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.organization.id == second.organization.id
      assert first.workspace.id == second.workspace.id
      assert first.initiative.id == second.initiative.id

      assert {1, 1, 1, 1} =
               with_unboxed_connection(fn ->
                 tenancy_scope_counts(organization_slug, workspace_slug, initiative_slug)
               end)
    after
      with_unboxed_connection(fn ->
        cleanup_tenancy_scope!(organization_slug)
        drop_tenancy_insert_barrier!()
      end)
    end
  end

  test "local owner bootstrap is idempotent under identity and authorization races" do
    suffix = System.unique_integer([:positive])

    attrs = [
      organization_name: "Owner Race #{suffix}",
      organization_slug: "owner-race-#{suffix}",
      workspace_name: "Owner Race Workspace #{suffix}",
      workspace_slug: "owner-race-workspace-#{suffix}",
      initiative_name: "Owner Race Initiative #{suffix}",
      initiative_slug: "owner-race-initiative-#{suffix}",
      owner_email: "owner-race-#{suffix}@office-graph.local",
      owner_name: "Owner Race #{suffix}"
    ]

    try do
      with_unboxed_connection(fn ->
        install_owner_bootstrap_insert_barriers!(attrs[:owner_email], attrs[:organization_slug])
      end)

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              capture_bootstrap_local_owner(attrs)
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.principal.id == second.principal.id
      assert first.profile.id == second.profile.id
      assert first.session.session_id == second.session.session_id
      assert first.role_assignment.id == second.role_assignment.id
      assert first.policy_bundle.id == second.policy_bundle.id

      assert {1, 1, 1, 1, 1} =
               with_unboxed_connection(fn ->
                 owner_bootstrap_counts(attrs[:organization_slug], attrs[:owner_email])
               end)
    after
      with_unboxed_connection(fn ->
        cleanup_bootstrap_scope!(attrs[:organization_slug], attrs[:owner_email])
        drop_owner_bootstrap_insert_barriers!()
      end)
    end
  end

  test "operation idempotency keys are race safe" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    idempotency_key = "operation-race-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    try do
      with_unboxed_connection(fn ->
        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )

        install_operation_insert_barrier!()
      end)

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              Operations.start_operation(session_context, :manual_intake_submit,
                idempotency_key: idempotency_key
              )
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.id == second.id

      assert 1 ==
               with_unboxed_connection(fn ->
                 operation_idempotency_count(organization_id, idempotency_key)
               end)
    after
      with_unboxed_connection(fn ->
        drop_operation_insert_barrier!()
        cleanup_committed_scope!(organization_id, principal_id, [])
      end)
    end
  end

  test "operation idempotency keys do not reuse another caller's operation" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    other_principal_id = Ecto.UUID.generate()
    other_session_id = Ecto.UUID.generate()
    idempotency_key = "operation-caller-scope-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    other_session_context = %SessionContext{
      principal_id: other_principal_id,
      session_id: other_session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    try do
      with_unboxed_connection(fn ->
        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )

        insert_additional_session_in_scope!(
          organization_id,
          workspace_id,
          other_principal_id,
          other_session_id,
          suffix
        )

        assert {:ok, first} =
                 Operations.start_operation(session_context, :manual_intake_submit,
                   idempotency_key: idempotency_key
                 )

        assert {:ok, second} =
                 Operations.start_operation(other_session_context, :manual_intake_submit,
                   idempotency_key: idempotency_key
                 )

        assert first.id != second.id
        assert first.principal_id == principal_id
        assert second.principal_id == other_principal_id

        assert 2 == operation_idempotency_count(organization_id, idempotency_key)
      end)
    after
      with_unboxed_connection(fn ->
        cleanup_committed_scope!(organization_id, [principal_id, other_principal_id], [])
      end)
    end
  end

  test "work packet creation is idempotent under operation replay races" do
    suffix = System.unique_integer([:positive])
    organization_slug = "work-packet-create-race-#{suffix}"
    workspace_slug = "work-packet-create-race-workspace-#{suffix}"
    owner_email = "work-packet-create-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, packet_operation, attrs} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Work Packet Create Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Work Packet Create Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Work Packet Create Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "packet-#{suffix}")

          {:ok, packet_operation} =
            Operations.start_operation(bootstrap.session, :work_packet_create,
              idempotency_key: "work-packet-create-race-#{suffix}"
            )

          install_work_packet_insert_barrier!(packet_operation.id)

          attrs = %{
            title: "Concurrent packet #{suffix}",
            objective: "Create one packet for one operation.",
            context_summary: "Concurrent packet creation context.",
            requirements: "Serialize packet creation.",
            success_criteria: "Only one packet is created.",
            autonomy_posture: "human_supervised",
            source_graph_item_ids: [verification_check.graph_item_id],
            verification_check_ids: [verification_check.id]
          }

          {bootstrap, packet_operation, attrs}
        end)

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              WorkPackets.create_packet(bootstrap.session, packet_operation, attrs)
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.packet.id == second.packet.id
      assert first.version.id == second.version.id

      assert {1, 1} =
               with_unboxed_connection(fn ->
                 packet_creation_counts(packet_operation.id)
               end)
    after
      with_unboxed_connection(fn ->
        drop_work_packet_insert_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "work run creation is idempotent under operation replay races" do
    suffix = System.unique_integer([:positive])
    organization_slug = "work-run-create-race-#{suffix}"
    workspace_slug = "work-run-create-race-workspace-#{suffix}"
    owner_email = "work-run-create-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, packet_version, run_operation} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Work Run Create Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Work Run Create Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Work Run Create Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "run-#{suffix}")

          {:ok, packet_result} =
            create_concurrency_ready_packet(bootstrap.session, [verification_check], suffix)

          {:ok, run_operation} =
            Operations.start_operation(bootstrap.session, :work_run_start,
              idempotency_key: "work-run-create-race-#{suffix}"
            )

          install_work_run_insert_barrier!(run_operation.id)

          {bootstrap, packet_result.version, run_operation}
        end)

      attrs = %{
        source_surface: "concurrency_test",
        reason: "Create one run for one operation.",
        authority_posture: "human_supervised"
      }

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              Runs.start_run(bootstrap.session, run_operation, packet_version, attrs)
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.run.id == second.run.id

      assert {1, 1} =
               with_unboxed_connection(fn ->
                 run_creation_counts(run_operation.id)
               end)
    after
      with_unboxed_connection(fn ->
        drop_work_run_insert_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

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

  defp submit_manual_intake(session_context, source_identity, replay_identity) do
    with {:ok, operation} <-
           Operations.start_operation(session_context, :manual_intake_submit,
             correlation_id: "source-race-#{replay_identity}"
           ) do
      Integrations.submit_manual_intake(session_context, operation, %{
        source_identity: source_identity,
        replay_identity: "paste:#{replay_identity}",
        body: "Task: verify concurrent manual intake source creation #{replay_identity}"
      })
    end
  end

  defp with_unboxed_connection(fun) do
    checkout = Sandbox.checkout(Repo, sandbox: false)

    try do
      fun.()
    after
      if checkout == :ok do
        Sandbox.checkin(Repo)
      end
    end
  end

  defp create_concurrency_verification_check(session, label) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "Concurrency signal #{label}",
             body: "Concurrency signal body #{label}."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "Concurrency task #{label}",
             body: "Concurrency task body #{label}."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "Concurrency finding #{label}",
             body: "Concurrency finding body #{label}."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "Concurrency check #{label}",
             body: "Concurrency check body #{label}."
           }) do
      {:ok, verification_check}
    end
  end

  defp create_concurrency_ready_run(session, verification_checks, suffix) do
    with {:ok, packet_result} <-
           create_concurrency_ready_packet(session, verification_checks, suffix),
         {:ok, run_operation} <-
           Operations.start_operation(session, :work_run_start,
             idempotency_key: "run-verification-race-run-#{suffix}"
           ) do
      Runs.start_run(session, run_operation, packet_result.version, %{
        source_surface: "concurrency_test",
        reason: "Exercise concurrent evidence acceptance.",
        authority_posture: "human_supervised"
      })
    end
  end

  defp create_concurrency_ready_packet(session, verification_checks, suffix) do
    {:ok, packet_operation} =
      Operations.start_operation(session, :work_packet_create,
        idempotency_key: "run-verification-race-packet-#{suffix}"
      )

    WorkPackets.create_packet(session, packet_operation, %{
      title: "Concurrency packet #{suffix}",
      objective: "Run concurrent evidence acceptance.",
      context_summary: "Concurrent acceptance context.",
      requirements: "Complete both required checks.",
      success_criteria: "Both checks have accepted evidence.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
      verification_check_ids: Enum.map(verification_checks, & &1.id)
    })
  end

  defp record_concurrency_observation(session, run, verification_check, key) do
    {:ok, operation} =
      Operations.start_operation(session, :execution_observation_record,
        idempotency_key: "run-verification-race-observation-operation-#{key}"
      )

    Runs.record_observation(session, operation, run, %{
      source_kind: "provider_check",
      source_identity: "provider:run-verification-race-#{key}",
      idempotency_key: "run-verification-race-observation-#{key}",
      observed_status: "success",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Provider check #{key} succeeded."
    })
  end

  defp standalone_observation_attrs(verification_check, source_identity, observation_key) do
    %{
      source_kind: "provider_check",
      source_identity: source_identity,
      idempotency_key: observation_key,
      observed_status: "passed",
      normalized_status: "succeeded",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Provider confirmed the standalone observation."
    }
  end

  defp create_concurrency_candidate(session, run, verification_check, observation, key) do
    {:ok, operation} =
      Operations.start_operation(session, :evidence_candidate_create,
        idempotency_key: "run-verification-race-candidate-#{key}"
      )

    Verification.create_evidence_candidate(session, operation, %{
      work_run_id: run.id,
      verification_check_id: verification_check.id,
      execution_observation_id: observation.id,
      claim: "Concurrency evidence candidate #{key}.",
      source_kind: "provider_check",
      source_identity: "provider:run-verification-race-#{key}",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      sensitivity: "internal"
    })
  end

  defp insert_minimal_session_scope!(
         organization_id,
         workspace_id,
         principal_id,
         session_id,
         suffix
       ) do
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO organizations (id, name, slug, inserted_at, updated_at)
      VALUES ($1::uuid, $2, $3, $4, $4)
      """,
      [db_uuid(organization_id), "Race Org #{suffix}", "race-org-#{suffix}", now]
    )

    Repo.query!(
      """
      INSERT INTO workspaces (id, organization_id, name, slug, inserted_at, updated_at)
      VALUES ($1::uuid, $2::uuid, $3, $4, $5, $5)
      """,
      [
        db_uuid(workspace_id),
        db_uuid(organization_id),
        "Race Workspace #{suffix}",
        "race-workspace-#{suffix}",
        now
      ]
    )

    Repo.query!(
      """
      INSERT INTO principals (id, email, kind, status, inserted_at, updated_at)
      VALUES ($1::uuid, $2, 'human', 'active', $3, $3)
      """,
      [db_uuid(principal_id), "race-#{suffix}@office-graph.local", now]
    )

    Repo.query!(
      """
      INSERT INTO sessions (
        id,
        principal_id,
        organization_id,
        workspace_id,
        purpose,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'source_race', $5, $5)
      """,
      [
        db_uuid(session_id),
        db_uuid(principal_id),
        db_uuid(organization_id),
        db_uuid(workspace_id),
        now
      ]
    )

    grant_owner_capabilities!(organization_id, workspace_id, principal_id, suffix)
  end

  defp grant_owner_capabilities!(organization_id, workspace_id, principal_id, suffix) do
    now = DateTime.utc_now()
    role_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO roles (id, organization_id, key, name, inserted_at, updated_at)
      VALUES ($1::uuid, $2::uuid, $3, 'Race Owner', $4, $4)
      """,
      [db_uuid(role_id), db_uuid(organization_id), "race-owner-#{suffix}", now]
    )

    role_assignment_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO role_assignments (
        id,
        principal_id,
        role_id,
        organization_id,
        workspace_id,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid, $6, $6)
      """,
      [
        db_uuid(role_assignment_id),
        db_uuid(principal_id),
        db_uuid(role_id),
        db_uuid(organization_id),
        db_uuid(workspace_id),
        now
      ]
    )

    for key <- [
          "skeleton.read",
          "manual_intake.submit",
          "proposed_change.apply",
          "evidence.link",
          "verification.complete"
        ] do
      capability_id = ensure_capability!(key)

      Repo.query!(
        """
        INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
        VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $4)
        ON CONFLICT (role_id, capability_id) DO NOTHING
        """,
        [db_uuid(Ecto.UUID.generate()), db_uuid(role_id), db_uuid(capability_id), now]
      )
    end
  end

  defp ensure_capability!(key) do
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
      VALUES ($1::uuid, $2, $2, $3, $3)
      ON CONFLICT (key) DO NOTHING
      """,
      [db_uuid(Ecto.UUID.generate()), key, now]
    )

    %{rows: [[capability_id]]} =
      Repo.query!("SELECT id FROM capabilities WHERE key = $1", [key])

    capability_id
  end

  defp insert_additional_session_in_scope!(
         organization_id,
         workspace_id,
         principal_id,
         session_id,
         suffix
       ) do
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO principals (id, email, kind, status, inserted_at, updated_at)
      VALUES ($1::uuid, $2, 'human', 'active', $3, $3)
      """,
      [db_uuid(principal_id), "operation-context-#{suffix}@office-graph.local", now]
    )

    Repo.query!(
      """
      INSERT INTO sessions (
        id,
        principal_id,
        organization_id,
        workspace_id,
        purpose,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'operation_context', $5, $5)
      """,
      [
        db_uuid(session_id),
        db_uuid(principal_id),
        db_uuid(organization_id),
        db_uuid(workspace_id),
        now
      ]
    )
  end

  defp capture_submit(session_context, operation, attrs) do
    Integrations.submit_manual_intake(session_context, operation, attrs)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp capture_create_for_manual_intake(session_context, operation, normalized_event, body) do
    ProposedChanges.create_for_manual_intake(session_context, operation, normalized_event, %{
      body: body
    })
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp capture_ensure_local_scope(attrs) do
    Tenancy.ensure_local_scope(attrs)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp capture_bootstrap_local_owner(attrs) do
    Foundation.bootstrap_local_owner(attrs)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp accepted_event_count(organization_id, source_identity, replay_identity) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM normalized_intake_events
        WHERE organization_id = $1::uuid
          AND source_identity = $2
          AND replay_identity = $3
          AND outcome = 'accepted'
        """,
        [db_uuid(organization_id), source_identity, replay_identity]
      )

    count
  end

  defp intake_record_count(organization_id, source_identity) do
    %{rows: [[raw_archive_count, normalized_event_count, proposed_change_count]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*)
           FROM raw_archives
           WHERE organization_id = $1::uuid),
          (SELECT count(*)
           FROM normalized_intake_events
           WHERE organization_id = $1::uuid
             AND source_identity = $2),
          (SELECT count(*)
           FROM proposed_graph_changes
           WHERE organization_id = $1::uuid)
        """,
        [db_uuid(organization_id), source_identity]
      )

    raw_archive_count + normalized_event_count + proposed_change_count
  end

  defp proposed_change_count(normalized_event_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM proposed_graph_changes
        WHERE normalized_event_id = $1::uuid
        """,
        [db_uuid(normalized_event_id)]
      )

    count
  end

  defp operation_idempotency_count(organization_id, idempotency_key) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM operation_correlations
        WHERE organization_id = $1::uuid
          AND idempotency_key = $2
        """,
        [db_uuid(organization_id), idempotency_key]
      )

    count
  end

  defp packet_creation_counts(operation_id) do
    %{rows: [[packet_count, version_count]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM work_packets WHERE operation_id = $1::uuid),
          (SELECT count(*) FROM work_packet_versions WHERE operation_id = $1::uuid)
        """,
        [db_uuid(operation_id)]
      )

    {packet_count, version_count}
  end

  defp run_creation_counts(operation_id) do
    %{rows: [[run_count, required_check_count]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM runs WHERE operation_id = $1::uuid),
          (SELECT count(*)
           FROM run_required_checks
           WHERE run_id IN (SELECT id FROM runs WHERE operation_id = $1::uuid))
        """,
        [db_uuid(operation_id)]
      )

    {run_count, required_check_count}
  end

  defp evidence_candidate_creation_count(operation_id) do
    %{rows: [[candidate_count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM evidence_candidates
        WHERE operation_id = $1::uuid
        """,
        [db_uuid(operation_id)]
      )

    candidate_count
  end

  defp evidence_acceptance_counts(candidate_id) do
    %{rows: [[evidence_item_count, verification_result_count]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM evidence_items WHERE candidate_id = $1::uuid),
          (SELECT count(*)
           FROM verification_results
           WHERE evidence_item_id IN (
             SELECT id FROM evidence_items WHERE candidate_id = $1::uuid
           ))
        """,
        [db_uuid(candidate_id)]
      )

    {evidence_item_count, verification_result_count}
  end

  defp evidence_acceptance_operation_counts(operation_id) do
    %{rows: [[evidence_item_count, verification_result_count]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM evidence_items WHERE acceptance_operation_id = $1::uuid),
          (SELECT count(*)
           FROM verification_results
           WHERE evidence_item_id IN (
             SELECT id FROM evidence_items WHERE acceptance_operation_id = $1::uuid
           ))
        """,
        [db_uuid(operation_id)]
      )

    {evidence_item_count, verification_result_count}
  end

  defp observation_source_key_count(source_identity, idempotency_key) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM execution_observations
        WHERE source_identity = $1
          AND idempotency_key = $2
        """,
        [source_identity, idempotency_key]
      )

    count
  end

  defp no_run_verification_result_count(verification_check_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM verification_results
        WHERE verification_check_id = $1::uuid
          AND work_run_id IS NULL
        """,
        [db_uuid(verification_check_id)]
      )

    count
  end

  defp owner_bootstrap_counts(organization_slug, owner_email) do
    %{rows: [[principal_count, profile_count, session_count, assignment_count, policy_count]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*)
           FROM principals
           WHERE email = $1),
          (SELECT count(*)
           FROM principal_profiles pp
           JOIN principals p ON p.id = pp.principal_id
           WHERE p.email = $1),
          (SELECT count(*)
           FROM sessions s
           JOIN principals p ON p.id = s.principal_id
           WHERE p.email = $1
             AND s.purpose = 'local_owner'),
          (SELECT count(*)
           FROM role_assignments ra
           JOIN principals p ON p.id = ra.principal_id
           WHERE p.email = $1),
          (SELECT count(*)
           FROM policy_bundles pb
           JOIN organizations o ON o.id = pb.organization_id
           WHERE o.slug = $2)
        """,
        [owner_email, organization_slug]
      )

    {principal_count, profile_count, session_count, assignment_count, policy_count}
  end

  defp insert_accepted_intake_event_without_proposed_changes!(
         session_context,
         operation,
         source_identity,
         replay_identity,
         body
       ) do
    now = DateTime.utc_now()
    source_id = Ecto.UUID.generate()
    raw_archive_id = Ecto.UUID.generate()
    normalized_event_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO external_sources (id, key, name, kind, inserted_at, updated_at)
      VALUES ($1::uuid, $2, 'Manual Intake', 'manual', $3, $3)
      """,
      [db_uuid(source_id), source_identity, now]
    )

    Repo.query!(
      """
      INSERT INTO raw_archives (
        id,
        organization_id,
        workspace_id,
        source_id,
        operation_id,
        content_hash,
        body,
        metadata,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid, $6, $7, '{}'::jsonb, $8, $8)
      """,
      [
        db_uuid(raw_archive_id),
        db_uuid(session_context.organization_id),
        db_uuid(session_context.workspace_id),
        db_uuid(source_id),
        db_uuid(operation.id),
        content_hash(body),
        body,
        now
      ]
    )

    Repo.query!(
      """
      INSERT INTO normalized_intake_events (
        id,
        organization_id,
        workspace_id,
        raw_archive_id,
        operation_id,
        source_identity,
        replay_identity,
        outcome,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid, $6, $7, 'accepted', $8, $8)
      """,
      [
        db_uuid(normalized_event_id),
        db_uuid(session_context.organization_id),
        db_uuid(session_context.workspace_id),
        db_uuid(raw_archive_id),
        db_uuid(operation.id),
        source_identity,
        replay_identity,
        now
      ]
    )

    %{
      id: normalized_event_id,
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id,
      operation_id: operation.id,
      outcome: "accepted"
    }
  end

  defp insert_external_source!(source_identity) do
    source_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO external_sources (id, key, name, kind, inserted_at, updated_at)
      VALUES ($1::uuid, $2, 'Manual Intake', 'manual', $3, $3)
      """,
      [db_uuid(source_id), source_identity, now]
    )

    source_id
  end

  defp insert_accepted_intake_event_for_source!(
         session_context,
         operation,
         source_id,
         source_identity,
         replay_identity,
         body
       ) do
    now = DateTime.utc_now()
    raw_archive_id = Ecto.UUID.generate()
    normalized_event_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO raw_archives (
        id,
        organization_id,
        workspace_id,
        source_id,
        operation_id,
        content_hash,
        body,
        metadata,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid, $6, $7, '{}'::jsonb, $8, $8)
      """,
      [
        db_uuid(raw_archive_id),
        db_uuid(session_context.organization_id),
        db_uuid(session_context.workspace_id),
        db_uuid(source_id),
        db_uuid(operation.id),
        content_hash(body),
        body,
        now
      ]
    )

    Repo.query!(
      """
      INSERT INTO normalized_intake_events (
        id,
        organization_id,
        workspace_id,
        raw_archive_id,
        operation_id,
        source_identity,
        replay_identity,
        outcome,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid, $6, $7, 'accepted', $8, $8)
      """,
      [
        db_uuid(normalized_event_id),
        db_uuid(session_context.organization_id),
        db_uuid(session_context.workspace_id),
        db_uuid(raw_archive_id),
        db_uuid(operation.id),
        source_identity,
        replay_identity,
        now
      ]
    )

    %{
      id: normalized_event_id,
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id,
      operation_id: operation.id,
      outcome: "accepted"
    }
  end

  defp content_hash(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
  end

  defp install_proposed_change_failure_trigger!(body) do
    %{rows: [[quoted_body]]} = Repo.query!("SELECT quote_literal($1)", [body])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_proposed_change_failure ON proposed_graph_changes"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_proposed_change_failure()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_proposed_change_failure()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.payload->>'body' = TG_ARGV[0] THEN
        RAISE EXCEPTION 'forced proposed graph change failure for manual intake atomicity';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_proposed_change_failure
    BEFORE INSERT ON proposed_graph_changes
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_proposed_change_failure(#{quoted_body})
    """)
  end

  defp drop_proposed_change_failure_trigger! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_proposed_change_failure ON proposed_graph_changes"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_proposed_change_failure()")
  end

  defp install_proposed_change_insert_barrier!(normalized_event_id) do
    %{rows: [[quoted_id]]} = Repo.query!("SELECT quote_literal($1)", [normalized_event_id])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_proposed_change_race_barrier ON proposed_graph_changes"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_proposed_change_race_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_proposed_change_race_barrier()
    RETURNS trigger AS $$
    DECLARE
      event_hash integer := hashtext(NEW.normalized_event_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.normalized_event_id = TG_ARGV[0]::uuid AND NEW.change_type = 'create_signal' THEN
        IF pg_try_advisory_lock(92001, event_hash) THEN
          LOOP
            IF pg_try_advisory_lock(92002, event_hash) THEN
              PERFORM pg_advisory_unlock(92002, event_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(92001, event_hash);
        ELSE
          PERFORM pg_advisory_lock(92002, event_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(92002, event_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_proposed_change_race_barrier
    BEFORE INSERT ON proposed_graph_changes
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_proposed_change_race_barrier(#{quoted_id})
    """)
  end

  defp drop_proposed_change_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_proposed_change_race_barrier ON proposed_graph_changes"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_proposed_change_race_barrier()")
  end

  defp install_raw_archive_body_wait!(body, lock_key) do
    %{rows: [[quoted_body]]} = Repo.query!("SELECT quote_literal($1)", [body])

    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_raw_archive_body_wait ON raw_archives")
    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_raw_archive_body_wait()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_raw_archive_body_wait()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.body = TG_ARGV[0] THEN
        PERFORM pg_advisory_lock(97001, TG_ARGV[1]::integer);
        PERFORM pg_advisory_unlock(97001, TG_ARGV[1]::integer);
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_raw_archive_body_wait
    BEFORE INSERT ON raw_archives
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_raw_archive_body_wait(#{quoted_body}, '#{lock_key}')
    """)
  end

  defp wait_for_blocked_raw_archive!(lock_key, attempts \\ 200)

  defp wait_for_blocked_raw_archive!(_lock_key, 0), do: flunk("raw archive insert did not block")

  defp wait_for_blocked_raw_archive!(lock_key, attempts) do
    waiting_count = blocked_raw_archive_count(lock_key)

    if waiting_count > 0 do
      :ok
    else
      Process.sleep(10)
      wait_for_blocked_raw_archive!(lock_key, attempts - 1)
    end
  end

  defp blocked_raw_archive_count(lock_key) do
    %{rows: [[waiting_count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM pg_locks
        WHERE locktype = 'advisory'
          AND classid = 97001
          AND objid = $1
          AND granted = false
        """,
        [lock_key]
      )

    waiting_count
  end

  defp drop_raw_archive_body_wait! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_raw_archive_body_wait ON raw_archives")
    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_raw_archive_body_wait()")
  end

  defp install_work_packet_insert_barrier!(operation_id) do
    %{rows: [[quoted_operation_id]]} = Repo.query!("SELECT quote_literal($1)", [operation_id])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_work_packet_insert_barrier ON work_packets"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_work_packet_insert_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_work_packet_insert_barrier()
    RETURNS trigger AS $$
    DECLARE
      operation_hash integer := hashtext(NEW.operation_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.operation_id = TG_ARGV[0]::uuid THEN
        IF pg_try_advisory_lock(98101, operation_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98102, operation_hash) THEN
              PERFORM pg_advisory_unlock(98102, operation_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98101, operation_hash);
        ELSE
          PERFORM pg_advisory_lock(98102, operation_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98102, operation_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_work_packet_insert_barrier
    BEFORE INSERT ON work_packets
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_work_packet_insert_barrier(#{quoted_operation_id})
    """)
  end

  defp drop_work_packet_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_work_packet_insert_barrier ON work_packets"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_work_packet_insert_barrier()")
  end

  defp install_work_run_insert_barrier!(operation_id) do
    %{rows: [[quoted_operation_id]]} = Repo.query!("SELECT quote_literal($1)", [operation_id])

    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_work_run_insert_barrier ON runs")
    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_work_run_insert_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_work_run_insert_barrier()
    RETURNS trigger AS $$
    DECLARE
      operation_hash integer := hashtext(NEW.operation_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.operation_id = TG_ARGV[0]::uuid THEN
        IF pg_try_advisory_lock(98201, operation_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98202, operation_hash) THEN
              PERFORM pg_advisory_unlock(98202, operation_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98201, operation_hash);
        ELSE
          PERFORM pg_advisory_lock(98202, operation_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98202, operation_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_work_run_insert_barrier
    BEFORE INSERT ON runs
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_work_run_insert_barrier(#{quoted_operation_id})
    """)
  end

  defp drop_work_run_insert_barrier! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_work_run_insert_barrier ON runs")
    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_work_run_insert_barrier()")
  end

  defp install_evidence_candidate_insert_barrier!(operation_id) do
    %{rows: [[quoted_operation_id]]} = Repo.query!("SELECT quote_literal($1)", [operation_id])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_candidate_insert_barrier ON evidence_candidates"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_evidence_candidate_insert_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_evidence_candidate_insert_barrier()
    RETURNS trigger AS $$
    DECLARE
      operation_hash integer := hashtext(NEW.operation_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.operation_id = TG_ARGV[0]::uuid THEN
        IF pg_try_advisory_lock(98251, operation_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98252, operation_hash) THEN
              PERFORM pg_advisory_unlock(98252, operation_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98251, operation_hash);
        ELSE
          PERFORM pg_advisory_lock(98252, operation_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98252, operation_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_evidence_candidate_insert_barrier
    BEFORE INSERT ON evidence_candidates
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_evidence_candidate_insert_barrier(#{quoted_operation_id})
    """)
  end

  defp drop_evidence_candidate_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_candidate_insert_barrier ON evidence_candidates"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_evidence_candidate_insert_barrier()")
  end

  defp install_evidence_item_insert_barrier!(candidate_id) do
    %{rows: [[quoted_candidate_id]]} = Repo.query!("SELECT quote_literal($1)", [candidate_id])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_item_insert_barrier ON evidence_items"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_evidence_item_insert_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_evidence_item_insert_barrier()
    RETURNS trigger AS $$
    DECLARE
      candidate_hash integer := hashtext(NEW.candidate_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.candidate_id = TG_ARGV[0]::uuid THEN
        IF pg_try_advisory_lock(98301, candidate_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98302, candidate_hash) THEN
              PERFORM pg_advisory_unlock(98302, candidate_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98301, candidate_hash);
        ELSE
          PERFORM pg_advisory_lock(98302, candidate_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98302, candidate_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_evidence_item_insert_barrier
    BEFORE INSERT ON evidence_items
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_evidence_item_insert_barrier(#{quoted_candidate_id})
    """)
  end

  defp drop_evidence_item_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_item_insert_barrier ON evidence_items"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_evidence_item_insert_barrier()")
  end

  defp install_evidence_item_operation_insert_barrier!(operation_id) do
    %{rows: [[quoted_operation_id]]} = Repo.query!("SELECT quote_literal($1)", [operation_id])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_item_operation_insert_barrier ON evidence_items"
    )

    Repo.query!(
      "DROP FUNCTION IF EXISTS office_graph_test_evidence_item_operation_insert_barrier()"
    )

    Repo.query!("""
    CREATE FUNCTION office_graph_test_evidence_item_operation_insert_barrier()
    RETURNS trigger AS $$
    DECLARE
      operation_hash integer := hashtext(NEW.acceptance_operation_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.acceptance_operation_id = TG_ARGV[0]::uuid THEN
        IF pg_try_advisory_lock(98351, operation_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98352, operation_hash) THEN
              PERFORM pg_advisory_unlock(98352, operation_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98351, operation_hash);
        ELSE
          PERFORM pg_advisory_lock(98352, operation_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98352, operation_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_evidence_item_operation_insert_barrier
    BEFORE INSERT ON evidence_items
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_evidence_item_operation_insert_barrier(#{quoted_operation_id})
    """)
  end

  defp drop_evidence_item_operation_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_item_operation_insert_barrier ON evidence_items"
    )

    Repo.query!(
      "DROP FUNCTION IF EXISTS office_graph_test_evidence_item_operation_insert_barrier()"
    )
  end

  defp install_run_required_check_update_barrier!(run_id) do
    %{rows: [[quoted_run_id]]} = Repo.query!("SELECT quote_literal($1)", [run_id])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_run_required_check_update_barrier ON run_required_checks"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_run_required_check_update_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_run_required_check_update_barrier()
    RETURNS trigger AS $$
    DECLARE
      run_hash integer := hashtext(NEW.run_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.run_id::text = TG_ARGV[0]
         AND OLD.state IS DISTINCT FROM NEW.state
         AND NEW.state = 'satisfied' THEN
        IF pg_try_advisory_lock(98001, run_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98002, run_hash) THEN
              PERFORM pg_advisory_unlock(98002, run_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98001, run_hash);
        ELSE
          PERFORM pg_advisory_lock(98002, run_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98002, run_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_run_required_check_update_barrier
    AFTER UPDATE ON run_required_checks
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_run_required_check_update_barrier(#{quoted_run_id})
    """)
  end

  defp drop_run_required_check_update_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_run_required_check_update_barrier ON run_required_checks"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_run_required_check_update_barrier()")
  end

  defp install_execution_observation_insert_barrier!(idempotency_key) do
    %{rows: [[quoted_idempotency_key]]} =
      Repo.query!("SELECT quote_literal($1)", [idempotency_key])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_execution_observation_insert_barrier ON execution_observations"
    )

    Repo.query!(
      "DROP FUNCTION IF EXISTS office_graph_test_execution_observation_insert_barrier()"
    )

    Repo.query!("""
    CREATE FUNCTION office_graph_test_execution_observation_insert_barrier()
    RETURNS trigger AS $$
    DECLARE
      key_hash integer := hashtext(NEW.idempotency_key);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.idempotency_key = TG_ARGV[0] THEN
        IF pg_try_advisory_lock(98101, key_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98102, key_hash) THEN
              PERFORM pg_advisory_unlock(98102, key_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98101, key_hash);
        ELSE
          PERFORM pg_advisory_lock(98102, key_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98102, key_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_execution_observation_insert_barrier
    BEFORE INSERT ON execution_observations
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_execution_observation_insert_barrier(#{quoted_idempotency_key})
    """)
  end

  defp drop_execution_observation_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_execution_observation_insert_barrier ON execution_observations"
    )

    Repo.query!(
      "DROP FUNCTION IF EXISTS office_graph_test_execution_observation_insert_barrier()"
    )
  end

  defp install_verification_result_insert_barrier!(verification_check_id) do
    %{rows: [[quoted_check_id]]} =
      Repo.query!("SELECT quote_literal($1)", [verification_check_id])

    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_verification_result_insert_barrier ON verification_results"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_verification_result_insert_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_verification_result_insert_barrier()
    RETURNS trigger AS $$
    DECLARE
      check_hash integer := hashtext(NEW.verification_check_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.verification_check_id::text = TG_ARGV[0]
         AND NEW.work_run_id IS NULL THEN
        IF pg_try_advisory_lock(98201, check_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98202, check_hash) THEN
              PERFORM pg_advisory_unlock(98202, check_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98201, check_hash);
        ELSE
          PERFORM pg_advisory_lock(98202, check_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98202, check_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_verification_result_insert_barrier
    BEFORE INSERT ON verification_results
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_verification_result_insert_barrier(#{quoted_check_id})
    """)
  end

  defp drop_verification_result_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_verification_result_insert_barrier ON verification_results"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_verification_result_insert_barrier()")
  end

  defp install_tenancy_insert_barrier! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_tenancy_race_barrier ON organizations")

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_tenancy_race_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_tenancy_race_barrier()
    RETURNS trigger AS $$
    DECLARE
      tenant_hash integer := hashtext(NEW.slug);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.slug LIKE 'tenant-race-%' THEN
        IF pg_try_advisory_lock(93001, tenant_hash) THEN
          LOOP
            IF pg_try_advisory_lock(93002, tenant_hash) THEN
              PERFORM pg_advisory_unlock(93002, tenant_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '2 seconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(93001, tenant_hash);
        ELSE
          PERFORM pg_advisory_lock(93002, tenant_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(93002, tenant_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_tenancy_race_barrier
    BEFORE INSERT ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_tenancy_race_barrier()
    """)
  end

  defp drop_tenancy_insert_barrier! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_tenancy_race_barrier ON organizations")

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_tenancy_race_barrier()")
  end

  defp install_operation_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_operation_race_barrier ON operation_correlations"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_operation_race_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_operation_race_barrier()
    RETURNS trigger AS $$
    DECLARE
      operation_hash integer := hashtext(NEW.idempotency_key);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.idempotency_key LIKE 'operation-race-%' THEN
        IF pg_try_advisory_lock(94001, operation_hash) THEN
          LOOP
            IF pg_try_advisory_lock(94002, operation_hash) THEN
              PERFORM pg_advisory_unlock(94002, operation_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '2 seconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(94001, operation_hash);
        ELSE
          PERFORM pg_advisory_lock(94002, operation_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(94002, operation_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_operation_race_barrier
    BEFORE INSERT ON operation_correlations
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_operation_race_barrier()
    """)
  end

  defp drop_operation_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_operation_race_barrier ON operation_correlations"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_operation_race_barrier()")
  end

  defp install_owner_bootstrap_insert_barriers!(owner_email, organization_slug) do
    %{rows: [[quoted_owner_email]]} = Repo.query!("SELECT quote_literal($1)", [owner_email])

    %{rows: [[quoted_organization_slug]]} =
      Repo.query!("SELECT quote_literal($1)", [organization_slug])

    drop_owner_bootstrap_insert_barriers!()

    Repo.query!("""
    CREATE FUNCTION office_graph_test_identity_race_barrier()
    RETURNS trigger AS $$
    DECLARE
      identity_hash integer := hashtext(NEW.email);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.email = TG_ARGV[0] THEN
        IF pg_try_advisory_lock(95001, identity_hash) THEN
          LOOP
            IF pg_try_advisory_lock(95002, identity_hash) THEN
              PERFORM pg_advisory_unlock(95002, identity_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '2 seconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(95001, identity_hash);
        ELSE
          PERFORM pg_advisory_lock(95002, identity_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(95002, identity_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_identity_race_barrier
    BEFORE INSERT ON principals
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_identity_race_barrier(#{quoted_owner_email})
    """)

    Repo.query!("""
    CREATE FUNCTION office_graph_test_authorization_race_barrier()
    RETURNS trigger AS $$
    DECLARE
      role_hash integer := hashtext(NEW.organization_id::text || ':' || NEW.key);
      started_at timestamp := clock_timestamp();
      organization_slug text;
    BEGIN
      SELECT slug INTO organization_slug
      FROM organizations
      WHERE id = NEW.organization_id;

      IF NEW.key = 'owner' AND organization_slug = TG_ARGV[0] THEN
        IF pg_try_advisory_lock(95003, role_hash) THEN
          LOOP
            IF pg_try_advisory_lock(95004, role_hash) THEN
              PERFORM pg_advisory_unlock(95004, role_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '2 seconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(95003, role_hash);
        ELSE
          PERFORM pg_advisory_lock(95004, role_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(95004, role_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_authorization_race_barrier
    BEFORE INSERT ON roles
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_authorization_race_barrier(#{quoted_organization_slug})
    """)
  end

  defp drop_owner_bootstrap_insert_barriers! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_identity_race_barrier ON principals")

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_identity_race_barrier()")

    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_authorization_race_barrier ON roles")

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_authorization_race_barrier()")
  end

  defp cleanup_owner_principal!(owner_email) do
    Repo.query!(
      """
      DELETE FROM principal_profiles
      WHERE principal_id IN (SELECT id FROM principals WHERE email = $1)
      """,
      [owner_email]
    )

    Repo.query!(
      """
      DELETE FROM principals
      WHERE email = $1
      """,
      [owner_email]
    )
  end

  defp install_source_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_source_race_barrier ON external_sources"
    )

    Repo.query!("""
    CREATE OR REPLACE FUNCTION office_graph_test_source_race_barrier()
    RETURNS trigger AS $$
    DECLARE
      source_hash integer := hashtext(NEW.key);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.key LIKE 'manual:source-race-%' THEN
        IF pg_try_advisory_lock(91001, source_hash) THEN
          LOOP
            IF pg_try_advisory_lock(91002, source_hash) THEN
              PERFORM pg_advisory_unlock(91002, source_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '2 seconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(91001, source_hash);
        ELSE
          PERFORM pg_advisory_lock(91002, source_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(91002, source_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_source_race_barrier
    BEFORE INSERT ON external_sources
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_source_race_barrier()
    """)
  end

  defp cleanup_committed_scope!(organization_id, principal_ids, source_identities) do
    cleanup_work_run_verification_scope_by_id!(organization_id)

    Repo.query!("DELETE FROM oban_jobs WHERE args->>'organization_id' = $1", [organization_id])

    Repo.query!("DELETE FROM domain_events WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM proposed_graph_changes WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM normalized_intake_events WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM raw_archives WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Enum.each(List.wrap(source_identities), fn source_identity ->
      Repo.query!("DELETE FROM external_sources WHERE key = $1", [source_identity])
    end)

    Repo.query!("DELETE FROM authorization_decisions WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM operation_correlations WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!(
      """
      DELETE FROM role_capabilities
      WHERE role_id IN (SELECT id FROM roles WHERE organization_id = $1::uuid)
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!("DELETE FROM role_assignments WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM roles WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM sessions WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM workspaces WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Enum.each(List.wrap(principal_ids), fn principal_id ->
      Repo.query!("DELETE FROM principals WHERE id = $1::uuid", [db_uuid(principal_id)])
    end)

    Repo.query!("DELETE FROM organizations WHERE id = $1::uuid", [db_uuid(organization_id)])
  end

  defp cleanup_work_run_verification_scope!(organization_slug) do
    Repo.query!(
      """
      DELETE FROM verification_results
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM evidence_items
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM evidence_candidates
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM execution_observations
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM run_required_checks
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM runs
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM work_packet_version_required_checks
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM work_packet_version_sources
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM work_packet_versions
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM work_packets
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM artifacts
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM verification_checks
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM review_findings
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM tasks
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM signals
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM graph_relationships
      WHERE source_item_id IN (
        SELECT gi.id
        FROM graph_items gi
        JOIN organizations o ON o.id = gi.organization_id
        WHERE o.slug = $1
      )
      OR target_item_id IN (
        SELECT gi.id
        FROM graph_items gi
        JOIN organizations o ON o.id = gi.organization_id
        WHERE o.slug = $1
      )
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM graph_items
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM documents
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM audit_records
      WHERE operation_id IN (
        SELECT oc.id
        FROM operation_correlations oc
        JOIN organizations o ON o.id = oc.organization_id
        WHERE o.slug = $1
      )
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM revisions
      WHERE operation_id IN (
        SELECT oc.id
        FROM operation_correlations oc
        JOIN organizations o ON o.id = oc.organization_id
        WHERE o.slug = $1
      )
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM authorization_decisions
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM operation_correlations
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )
  end

  defp cleanup_work_run_verification_scope_by_id!(organization_id) do
    Repo.query!(
      """
      DELETE FROM verification_results
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM evidence_items
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM evidence_candidates
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM execution_observations
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM run_required_checks
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM runs
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM work_packet_version_required_checks
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM work_packet_version_sources
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM work_packet_versions
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM work_packets
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM artifacts
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM verification_checks
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM review_findings
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM tasks
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM signals
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM graph_relationships
      WHERE source_item_id IN (
        SELECT id FROM graph_items WHERE organization_id = $1::uuid
      )
      OR target_item_id IN (
        SELECT id FROM graph_items WHERE organization_id = $1::uuid
      )
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM graph_items
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM documents
      WHERE organization_id = $1::uuid
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM audit_records
      WHERE operation_id IN (
        SELECT id FROM operation_correlations WHERE organization_id = $1::uuid
      )
      """,
      [db_uuid(organization_id)]
    )

    Repo.query!(
      """
      DELETE FROM revisions
      WHERE operation_id IN (
        SELECT id FROM operation_correlations WHERE organization_id = $1::uuid
      )
      """,
      [db_uuid(organization_id)]
    )
  end

  defp drop_source_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_source_race_barrier ON external_sources"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_source_race_barrier()")
  end

  defp tenancy_scope_counts(organization_slug, workspace_slug, initiative_slug) do
    %{rows: [[organization_count, workspace_count, initiative_count, workstream_count]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM organizations WHERE slug = $1),
          (SELECT count(*)
           FROM workspaces
           WHERE slug = $2
             AND organization_id IN (SELECT id FROM organizations WHERE slug = $1)),
          (SELECT count(*)
           FROM initiatives
           WHERE slug = $3
             AND organization_id IN (SELECT id FROM organizations WHERE slug = $1)),
          (SELECT count(*)
           FROM workstreams
           WHERE slug = 'default'
             AND organization_id IN (SELECT id FROM organizations WHERE slug = $1))
        """,
        [organization_slug, workspace_slug, initiative_slug]
      )

    {organization_count, workspace_count, initiative_count, workstream_count}
  end

  defp cleanup_tenancy_scope!(organization_slug) do
    Repo.query!(
      """
      DELETE FROM role_capabilities
      WHERE role_id IN (
        SELECT r.id
        FROM roles r
        JOIN organizations o ON o.id = r.organization_id
        WHERE o.slug = $1
      )
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM role_assignments
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM policy_bundles
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM roles
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM sessions
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM workstreams
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM initiatives
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM workspaces
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!("DELETE FROM organizations WHERE slug = $1", [organization_slug])
  end

  defp cleanup_bootstrap_scope!(organization_slug, owner_email) do
    cleanup_tenancy_scope!(organization_slug)
    cleanup_owner_principal!(owner_email)
  end

  defp db_uuid(<<_::128>> = uuid), do: uuid
  defp db_uuid(uuid), do: Ecto.UUID.dump!(uuid)
end
