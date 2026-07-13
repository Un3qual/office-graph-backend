defmodule OfficeGraph.Integrations.IntakeBootstrapConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

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
end
