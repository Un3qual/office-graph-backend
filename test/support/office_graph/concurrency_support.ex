defmodule OfficeGraph.TestSupport.ConcurrencySupport do
  @moduledoc false

  require Ash.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias OfficeGraph.Authorization.{Capability, PolicyBundle, Role, RoleAssignment, RoleCapability}
  alias OfficeGraph.Identity.{Principal, PrincipalProfile, Session}
  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.Operations.OperationCorrelation
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
  alias OfficeGraph.Tenancy.{Organization, Workspace}
  alias OfficeGraph.WorkGraph.{EvidenceCandidate, EvidenceItem, VerificationResult}
  alias OfficeGraph.WorkPackets.{WorkPacket, WorkPacketVersion}

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
    proposed_change_insert_barrier:
      {:before_insert, "office_graph_test_proposed_change_race_barrier", "proposed_graph_changes"},
    work_packet_insert_barrier:
      {:before_insert, "office_graph_test_work_packet_insert_barrier", "work_packets"},
    work_run_insert_barrier:
      {:before_insert, "office_graph_test_work_run_insert_barrier", "runs"},
    conversation_insert_barrier:
      {:before_insert, "office_graph_test_conversation_insert_barrier", "conversations"},
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
       "verification_results"}
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
        NodeConversations,
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
    owner = Sandbox.start_owner!(Repo, sandbox: false)

    try do
      fun.()
    after
      Sandbox.stop_owner(owner)
    end
  end

  def run_concurrently(funs, timeout \\ 15_000) when is_list(funs) do
    parent = self()
    gate = make_ref()

    tasks =
      Enum.map(funs, fn fun ->
        Task.async(fn ->
          send(parent, {gate, :ready, self()})

          receive do
            {^gate, :go} -> with_unboxed_connection(fun)
          end
        end)
      end)

    ready_pids =
      Enum.map(tasks, fn _task ->
        receive do
          {^gate, :ready, pid} -> pid
        after
          timeout -> raise "concurrent test owner did not reach the start gate"
        end
      end)

    Enum.each(ready_pids, &send(&1, {gate, :go}))
    Task.await_many(tasks, timeout)
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
    create!(Organization, %{
      id: organization_id,
      name: "Race Org #{suffix}",
      slug: "race-org-#{suffix}"
    })

    create!(Workspace, %{
      id: workspace_id,
      organization_id: organization_id,
      name: "Race Workspace #{suffix}",
      slug: "race-workspace-#{suffix}"
    })

    create!(Principal, %{
      id: principal_id,
      email: "race-#{suffix}@office-graph.local",
      kind: "human",
      status: "active"
    })

    create!(Session, %{
      id: session_id,
      principal_id: principal_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      purpose: "source_race"
    })

    grant_owner_capabilities!(organization_id, workspace_id, principal_id, suffix)
  end

  def grant_owner_capabilities!(organization_id, workspace_id, principal_id, suffix) do
    role_id = Ecto.UUID.generate()

    create!(Role, %{
      id: role_id,
      organization_id: organization_id,
      key: "race-owner-#{suffix}",
      name: "Race Owner"
    })

    create!(RoleAssignment, %{
      id: Ecto.UUID.generate(),
      principal_id: principal_id,
      role_id: role_id,
      organization_id: organization_id,
      workspace_id: workspace_id
    })

    for key <- [
          "skeleton.read",
          "manual_intake.submit",
          "proposed_change.apply",
          "evidence.link",
          "verification.complete"
        ] do
      capability_id = ensure_capability!(key)

      ensure!(RoleCapability, %{role_id: role_id, capability_id: capability_id})
    end
  end

  def ensure_capability!(key) do
    Capability
    |> ensure!(%{key: key, description: key})
    |> Map.fetch!(:id)
  end

  def insert_additional_session_in_scope!(
        organization_id,
        workspace_id,
        principal_id,
        session_id,
        suffix
      ) do
    create!(Principal, %{
      id: principal_id,
      email: "operation-context-#{suffix}@office-graph.local",
      kind: "human",
      status: "active"
    })

    create!(Session, %{
      id: session_id,
      principal_id: principal_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      purpose: "operation_context"
    })
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
    NormalizedIntakeEvent
    |> Ash.Query.filter(
      organization_id == ^organization_id and
        source_identity == ^source_identity and
        replay_identity == ^replay_identity and
        outcome == "accepted"
    )
    |> count!()
  end

  def intake_record_count(organization_id, source_identity) do
    raw_archive_count =
      RawArchive
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> count!()

    normalized_event_count =
      NormalizedIntakeEvent
      |> Ash.Query.filter(
        organization_id == ^organization_id and source_identity == ^source_identity
      )
      |> count!()

    proposed_change_count =
      ProposedGraphChange
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> count!()

    raw_archive_count + normalized_event_count + proposed_change_count
  end

  def proposed_change_count(normalized_event_id) do
    ProposedGraphChange
    |> Ash.Query.filter(normalized_event_id == ^normalized_event_id)
    |> count!()
  end

  def operation_idempotency_count(organization_id, idempotency_key) do
    OperationCorrelation
    |> Ash.Query.filter(
      organization_id == ^organization_id and idempotency_key == ^idempotency_key
    )
    |> count!()
  end

  def packet_creation_counts(operation_id) do
    packet_count =
      WorkPacket
      |> Ash.Query.filter(operation_id == ^operation_id)
      |> count!()

    version_count =
      WorkPacketVersion
      |> Ash.Query.filter(operation_id == ^operation_id)
      |> count!()

    {packet_count, version_count}
  end

  def run_creation_counts(operation_id) do
    runs =
      Run
      |> Ash.Query.filter(operation_id == ^operation_id)
      |> Ash.read!(authorize?: false)

    run_ids = Enum.map(runs, & &1.id)

    required_check_count =
      RunRequiredCheck
      |> Ash.Query.filter(run_id in ^run_ids)
      |> count!()

    {length(runs), required_check_count}
  end

  def evidence_candidate_creation_count(operation_id) do
    EvidenceCandidate
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> count!()
  end

  def evidence_acceptance_counts(candidate_id) do
    items =
      EvidenceItem
      |> Ash.Query.filter(candidate_id == ^candidate_id)
      |> Ash.read!(authorize?: false)

    item_ids = Enum.map(items, & &1.id)

    result_count =
      VerificationResult
      |> Ash.Query.filter(evidence_item_id in ^item_ids)
      |> count!()

    {length(items), result_count}
  end

  def evidence_acceptance_operation_counts(operation_id) do
    items =
      EvidenceItem
      |> Ash.Query.filter(acceptance_operation_id == ^operation_id)
      |> Ash.read!(authorize?: false)

    item_ids = Enum.map(items, & &1.id)

    result_count =
      VerificationResult
      |> Ash.Query.filter(evidence_item_id in ^item_ids)
      |> count!()

    {length(items), result_count}
  end

  def observation_source_key_count(source_identity, idempotency_key) do
    ExecutionObservation
    |> Ash.Query.filter(
      source_identity == ^source_identity and idempotency_key == ^idempotency_key
    )
    |> count!()
  end

  def no_run_verification_result_count(verification_check_id) do
    VerificationResult
    |> Ash.Query.filter(verification_check_id == ^verification_check_id and is_nil(work_run_id))
    |> count!()
  end

  def run_verification_result_count(run_id, verification_check_id) do
    VerificationResult
    |> Ash.Query.filter(
      work_run_id == ^run_id and verification_check_id == ^verification_check_id
    )
    |> count!()
  end

  def owner_bootstrap_counts(organization_slug, owner_email) do
    principals =
      Principal
      |> Ash.Query.filter(email == ^owner_email)
      |> Ash.read!(authorize?: false)

    principal_ids = Enum.map(principals, & &1.id)

    organization_ids =
      Organization
      |> Ash.Query.filter(slug == ^organization_slug)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    profile_count =
      PrincipalProfile
      |> Ash.Query.filter(principal_id in ^principal_ids)
      |> count!()

    session_count =
      Session
      |> Ash.Query.filter(principal_id in ^principal_ids and purpose == "local_owner")
      |> count!()

    assignment_count =
      RoleAssignment
      |> Ash.Query.filter(principal_id in ^principal_ids)
      |> count!()

    policy_count =
      PolicyBundle
      |> Ash.Query.filter(organization_id in ^organization_ids)
      |> count!()

    {length(principals), profile_count, session_count, assignment_count, policy_count}
  end

  def insert_accepted_intake_event_without_proposed_changes!(
        session_context,
        operation,
        source_identity,
        replay_identity,
        body
      ) do
    source_id = insert_external_source!(source_identity)

    insert_accepted_intake_event_for_source!(
      session_context,
      operation,
      source_id,
      source_identity,
      replay_identity,
      body
    )
  end

  def insert_external_source!(source_identity) do
    ExternalSource
    |> create!(%{
      id: Ecto.UUID.generate(),
      key: source_identity,
      name: "Manual Intake",
      kind: "manual"
    })
    |> Map.fetch!(:id)
  end

  def insert_accepted_intake_event_for_source!(
        session_context,
        operation,
        source_id,
        source_identity,
        replay_identity,
        body
      ) do
    raw_archive_id = Ecto.UUID.generate()

    create!(RawArchive, %{
      id: raw_archive_id,
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id,
      source_id: source_id,
      operation_id: operation.id,
      content_hash: content_hash(body),
      body: body
    })

    create!(NormalizedIntakeEvent, %{
      id: Ecto.UUID.generate(),
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id,
      raw_archive_id: raw_archive_id,
      operation_id: operation.id,
      source_identity: source_identity,
      replay_identity: replay_identity,
      outcome: "accepted"
    })
  end

  def content_hash(body) do
    :crypto.hash(:sha256, body)
    |> Base.encode16(case: :lower)
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

  def install_conversation_insert_barrier!(run_id, graph_item_id) do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_conversation_insert_barrier ON conversations"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_conversation_insert_barrier()")

    Repo.query!("""
    CREATE FUNCTION office_graph_test_conversation_insert_barrier()
    RETURNS trigger AS $$
    DECLARE
      scope_hash integer := hashtext(NEW.run_id::text || ':' || NEW.graph_item_id::text);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.run_id = TG_ARGV[0]::uuid AND NEW.graph_item_id = TG_ARGV[1]::uuid THEN
        IF pg_try_advisory_lock(98211, scope_hash) THEN
          LOOP
            IF pg_try_advisory_lock(98212, scope_hash) THEN
              PERFORM pg_advisory_unlock(98212, scope_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '500 milliseconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(98211, scope_hash);
        ELSE
          PERFORM pg_advisory_lock(98212, scope_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(98212, scope_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    create_test_trigger!(:conversation_insert_barrier, [run_id, graph_item_id])
  end

  def drop_conversation_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_conversation_insert_barrier ON conversations"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_conversation_insert_barrier()")
  end

  def conversation_count(run_id, graph_item_id) do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(*) FROM conversations WHERE run_id = $1 AND graph_item_id = $2",
        [db_uuid(run_id), db_uuid(graph_item_id)]
      )

    count
  end

  def cleanup_conversation_scope!(organization_slug) do
    Repo.query!(
      """
      DELETE FROM conversation_messages
      WHERE conversation_id IN (
        SELECT conversation.id
        FROM conversations AS conversation
        JOIN organizations AS organization ON organization.id = conversation.organization_id
        WHERE organization.slug = $1
      )
      """,
      [organization_slug]
    )

    Repo.query!(
      """
      DELETE FROM conversations
      WHERE organization_id IN (SELECT id FROM organizations WHERE slug = $1)
      """,
      [organization_slug]
    )
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

  defp create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(authorize?: false)
  end

  defp ensure!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:ensure, attrs)
    |> Ash.create!(authorize?: false)
  end

  defp count!(query), do: Ash.count!(query, authorize?: false)

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
