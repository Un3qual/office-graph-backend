defmodule OfficeGraph.Integrations.ConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.{Integrations, Operations, Repo, Tenancy}

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

    Repo.query!("DELETE FROM operation_correlations WHERE organization_id = $1::uuid", [
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

  defp db_uuid(uuid), do: Ecto.UUID.dump!(uuid)
end
