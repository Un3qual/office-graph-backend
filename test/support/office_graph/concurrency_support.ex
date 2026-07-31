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

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case, async: false

      alias Ecto.Adapters.SQL.Sandbox
      alias OfficeGraph.Identity.SessionContext
      alias OfficeGraph.ProposedChanges
      alias OfficeGraph.TestSupport.ConcurrencyCleanup

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
end
