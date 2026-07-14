defmodule OfficeGraph.TestSupport.ConcurrencySupport do
  @moduledoc false

  import ExUnit.Assertions

  alias Ecto.Adapters.SQL.Sandbox
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

  @test_trigger_specs %{
    proposed_change_failure:
      {:before_insert, "office_graph_test_proposed_change_failure", "proposed_graph_changes"},
    proposed_change_insert_barrier:
      {:before_insert, "office_graph_test_proposed_change_race_barrier", "proposed_graph_changes"},
    raw_archive_body_wait:
      {:before_insert, "office_graph_test_raw_archive_body_wait", "raw_archives"},
    work_packet_insert_barrier:
      {:before_insert, "office_graph_test_work_packet_insert_barrier", "work_packets"},
    work_run_insert_barrier:
      {:before_insert, "office_graph_test_work_run_insert_barrier", "runs"},
    evidence_candidate_insert_barrier:
      {:before_insert, "office_graph_test_evidence_candidate_insert_barrier",
       "evidence_candidates"},
    evidence_item_insert_barrier:
      {:before_insert, "office_graph_test_evidence_item_insert_barrier", "evidence_items"},
    evidence_item_operation_insert_barrier:
      {:before_insert, "office_graph_test_evidence_item_operation_insert_barrier",
       "evidence_items"},
    run_required_check_update_barrier:
      {:after_update, "office_graph_test_run_required_check_update_barrier",
       "run_required_checks"},
    execution_observation_insert_barrier:
      {:before_insert, "office_graph_test_execution_observation_insert_barrier",
       "execution_observations"},
    verification_result_insert_barrier:
      {:before_insert, "office_graph_test_verification_result_insert_barrier",
       "verification_results"},
    identity_insert_barrier:
      {:before_insert, "office_graph_test_identity_race_barrier", "principals"},
    authorization_insert_barrier:
      {:before_insert, "office_graph_test_authorization_race_barrier", "roles"}
  }

  defmacro __using__(_opts) do
    quote do
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

      import OfficeGraph.TestSupport.ConcurrencySupport
    end
  end

  def submit_manual_intake(session_context, source_identity, replay_identity) do
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

  def with_unboxed_connection(fun) do
    checkout = Sandbox.checkout(Repo, sandbox: false)

    try do
      fun.()
    after
      if checkout == :ok do
        Sandbox.checkin(Repo)
      end
    end
  end

  def create_concurrency_verification_check(session, label) do
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

  def create_concurrency_ready_run(session, verification_checks, suffix) do
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

  def create_concurrency_ready_packet(session, verification_checks, suffix) do
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

  def record_concurrency_observation(session, run, verification_check, key) do
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

  def standalone_observation_attrs(verification_check, source_identity, observation_key) do
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

  def create_concurrency_candidate(session, run, verification_check, observation, key) do
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

  def insert_minimal_session_scope!(
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

  def grant_owner_capabilities!(organization_id, workspace_id, principal_id, suffix) do
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

  def ensure_capability!(key) do
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

  def insert_additional_session_in_scope!(
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

  def capture_submit(session_context, operation, attrs) do
    Integrations.submit_manual_intake(session_context, operation, attrs)
  catch
    :error, error -> {:error, error}
    :exit, reason -> {:error, reason}
  end

  def capture_create_for_manual_intake(session_context, operation, normalized_event, body) do
    ProposedChanges.create_for_manual_intake(session_context, operation, normalized_event, %{
      body: body
    })
  catch
    :error, error -> {:error, error}
    :exit, reason -> {:error, reason}
  end

  def capture_ensure_local_scope(attrs) do
    Tenancy.ensure_local_scope(attrs)
  catch
    :error, error -> {:error, error}
    :exit, reason -> {:error, reason}
  end

  def capture_bootstrap_local_owner(attrs) do
    Foundation.bootstrap_local_owner(attrs)
  catch
    :error, error -> {:error, error}
    :exit, reason -> {:error, reason}
  end

  def accepted_event_count(organization_id, source_identity, replay_identity) do
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

  def intake_record_count(organization_id, source_identity) do
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

  def proposed_change_count(normalized_event_id) do
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

  def operation_idempotency_count(organization_id, idempotency_key) do
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

  def packet_creation_counts(operation_id) do
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

  def run_creation_counts(operation_id) do
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

  def evidence_candidate_creation_count(operation_id) do
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

  def evidence_acceptance_counts(candidate_id) do
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

  def evidence_acceptance_operation_counts(operation_id) do
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

  def observation_source_key_count(source_identity, idempotency_key) do
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

  def no_run_verification_result_count(verification_check_id) do
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

  def run_verification_result_count(run_id, verification_check_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*)
        FROM verification_results
        WHERE work_run_id = $1::uuid
          AND verification_check_id = $2::uuid
        """,
        [db_uuid(run_id), db_uuid(verification_check_id)]
      )

    count
  end

  def owner_bootstrap_counts(organization_slug, owner_email) do
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

  def insert_accepted_intake_event_without_proposed_changes!(
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

  def insert_external_source!(source_identity) do
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

  def insert_accepted_intake_event_for_source!(
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

  def content_hash(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
  end

  def install_proposed_change_failure_trigger!(body) do
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

    create_test_trigger!(:proposed_change_failure, [body])
  end

  def drop_proposed_change_failure_trigger! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_proposed_change_failure ON proposed_graph_changes"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_proposed_change_failure()")
  end

  def install_proposed_change_insert_barrier!(normalized_event_id) do
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

    create_test_trigger!(:proposed_change_insert_barrier, [normalized_event_id])
  end

  def drop_proposed_change_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_proposed_change_race_barrier ON proposed_graph_changes"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_proposed_change_race_barrier()")
  end

  def install_raw_archive_body_wait!(body, lock_key) do
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

    create_test_trigger!(:raw_archive_body_wait, [body, lock_key])
  end

  def wait_for_blocked_raw_archive!(lock_key, attempts \\ 200)

  def wait_for_blocked_raw_archive!(_lock_key, 0),
    do: flunk("raw archive insert did not block")

  def wait_for_blocked_raw_archive!(lock_key, attempts) do
    waiting_count = blocked_raw_archive_count(lock_key)

    if waiting_count > 0 do
      :ok
    else
      Process.sleep(10)
      wait_for_blocked_raw_archive!(lock_key, attempts - 1)
    end
  end

  def blocked_raw_archive_count(lock_key) do
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

  def drop_raw_archive_body_wait! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_raw_archive_body_wait ON raw_archives")

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_raw_archive_body_wait()")
  end

  def install_work_packet_insert_barrier!(operation_id) do
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

    create_test_trigger!(:work_packet_insert_barrier, [operation_id])
  end

  def drop_work_packet_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_work_packet_insert_barrier ON work_packets"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_work_packet_insert_barrier()")
  end

  def install_work_run_insert_barrier!(operation_id) do
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

    create_test_trigger!(:work_run_insert_barrier, [operation_id])
  end

  def drop_work_run_insert_barrier! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_work_run_insert_barrier ON runs")
    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_work_run_insert_barrier()")
  end

  def install_evidence_candidate_insert_barrier!(operation_id) do
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

    create_test_trigger!(:evidence_candidate_insert_barrier, [operation_id])
  end

  def drop_evidence_candidate_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_candidate_insert_barrier ON evidence_candidates"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_evidence_candidate_insert_barrier()")
  end

  def install_evidence_item_insert_barrier!(candidate_id) do
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

    create_test_trigger!(:evidence_item_insert_barrier, [candidate_id])
  end

  def drop_evidence_item_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_item_insert_barrier ON evidence_items"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_evidence_item_insert_barrier()")
  end

  def install_evidence_item_operation_insert_barrier!(operation_id) do
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

    create_test_trigger!(:evidence_item_operation_insert_barrier, [operation_id])
  end

  def drop_evidence_item_operation_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_evidence_item_operation_insert_barrier ON evidence_items"
    )

    Repo.query!(
      "DROP FUNCTION IF EXISTS office_graph_test_evidence_item_operation_insert_barrier()"
    )
  end

  def install_run_required_check_update_barrier!(run_id) do
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

    create_test_trigger!(:run_required_check_update_barrier, [run_id])
  end

  def drop_run_required_check_update_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_run_required_check_update_barrier ON run_required_checks"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_run_required_check_update_barrier()")
  end

  def install_execution_observation_insert_barrier!(idempotency_key) do
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

    create_test_trigger!(:execution_observation_insert_barrier, [idempotency_key])
  end

  def drop_execution_observation_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_execution_observation_insert_barrier ON execution_observations"
    )

    Repo.query!(
      "DROP FUNCTION IF EXISTS office_graph_test_execution_observation_insert_barrier()"
    )
  end

  def install_verification_result_insert_barrier!(verification_check_id) do
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

    create_test_trigger!(:verification_result_insert_barrier, [verification_check_id])
  end

  def drop_verification_result_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_verification_result_insert_barrier ON verification_results"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_verification_result_insert_barrier()")
  end

  def install_tenancy_insert_barrier! do
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

  def drop_tenancy_insert_barrier! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_tenancy_race_barrier ON organizations")

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_tenancy_race_barrier()")
  end

  def install_operation_insert_barrier! do
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

  def drop_operation_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_operation_race_barrier ON operation_correlations"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_operation_race_barrier()")
  end

  def install_owner_bootstrap_insert_barriers!(owner_email, organization_slug) do
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

    create_test_trigger!(:identity_insert_barrier, [owner_email])

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

    create_test_trigger!(:authorization_insert_barrier, [organization_slug])
  end

  def drop_owner_bootstrap_insert_barriers! do
    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_identity_race_barrier ON principals")

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_identity_race_barrier()")

    Repo.query!("DROP TRIGGER IF EXISTS office_graph_test_authorization_race_barrier ON roles")

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_authorization_race_barrier()")
  end

  def cleanup_owner_principal!(owner_email) do
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

  def install_source_insert_barrier! do
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

  def cleanup_committed_scope!(organization_id, principal_ids, source_identities) do
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

  def cleanup_work_run_verification_scope!(organization_slug) do
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
      DELETE FROM oban_jobs
      WHERE args->>'organization_id' IN (
        SELECT id::text FROM organizations WHERE slug = $1
      )
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM domain_events
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM proposed_graph_changes
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM normalized_intake_events
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM raw_archives
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

  def cleanup_work_run_verification_scope_by_id!(organization_id) do
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

  def drop_source_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_source_race_barrier ON external_sources"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_source_race_barrier()")
  end

  def tenancy_scope_counts(organization_slug, workspace_slug, initiative_slug) do
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

  def cleanup_tenancy_scope!(organization_slug) do
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

  def cleanup_bootstrap_scope!(organization_slug, owner_email) do
    cleanup_tenancy_scope!(organization_slug)
    cleanup_owner_principal!(owner_email)
  end

  def db_uuid(<<_::128>> = uuid), do: uuid
  def db_uuid(uuid), do: Ecto.UUID.dump!(uuid)

  defp create_test_trigger!(spec_name, arguments) do
    {event, trigger_name, table_name} = Map.fetch!(@test_trigger_specs, spec_name)

    sql =
      [
        "CREATE TRIGGER ",
        quote_sql_identifier!(trigger_name),
        "\n",
        trigger_event_sql(event),
        " ON ",
        quote_sql_identifier!(table_name),
        "\nFOR EACH ROW\nEXECUTE FUNCTION ",
        quote_sql_identifier!(trigger_name),
        "(",
        arguments |> Enum.map(&quote_trigger_argument!/1) |> Enum.intersperse(", "),
        ")"
      ]
      |> IO.iodata_to_binary()

    Repo.query!(sql)
  end

  defp quote_sql_identifier!(identifier) do
    if Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, identifier) do
      ~s("#{identifier}")
    else
      raise ArgumentError, "unsafe internal test SQL identifier"
    end
  end

  defp quote_trigger_argument!(value) do
    case Repo.query!("SELECT quote_literal($1::text)", [to_string(value)]) do
      %{rows: [[quoted]]} when is_binary(quoted) -> quoted
      _result -> raise ArgumentError, "trigger arguments must be non-null scalar values"
    end
  end

  defp trigger_event_sql(:before_insert), do: "BEFORE INSERT"
  defp trigger_event_sql(:after_update), do: "AFTER UPDATE"
end
