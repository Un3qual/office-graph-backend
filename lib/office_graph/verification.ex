defmodule OfficeGraph.Verification do
  @moduledoc """
  Public boundary for verification checks, evidence, and results.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Content,
      OfficeGraph.Repo,
      OfficeGraph.Runs,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.Content
  alias OfficeGraph.Repo
  alias OfficeGraph.Runs
  alias OfficeGraph.WorkGraph

  alias OfficeGraph.Runs.{ExecutionObservation, Run}

  alias OfficeGraph.WorkGraph.{
    EvidenceCandidate,
    EvidenceItem,
    GraphItem,
    VerificationCheck,
    VerificationResult
  }

  require Ash.Query

  @evidence_candidate_create_action "evidence_candidate.create"
  @evidence_accept_action "evidence.accept"

  def complete_with_evidence(session_context, operation, verification_check, attrs) do
    with :ok <-
           Authorization.authorize_operation(session_context, operation, :evidence_link,
             organization_id: verification_check.organization_id
           ),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :verification_complete,
             organization_id: verification_check.organization_id
           ) do
      WorkGraph.complete_verification(session_context, operation, verification_check, attrs)
    end
  end

  def create_evidence_candidate(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @evidence_candidate_create_action),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :evidence_candidate_create,
             organization_id: session_context.organization_id
           ),
         :ok <- validate_referenced_scope(session_context, attrs) do
      EvidenceCandidate
      |> Ash.Changeset.for_create(:create, %{
        id: Ecto.UUID.generate(),
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        verification_check_id: attrs[:verification_check_id],
        work_run_id: attrs[:work_run_id],
        execution_observation_id: attrs[:execution_observation_id],
        artifact_id: attrs[:artifact_id],
        operation_id: operation.id,
        claim: attrs[:claim],
        source_kind: attrs[:source_kind],
        source_identity: attrs[:source_identity],
        freshness_state: attrs[:freshness_state],
        trust_basis: attrs[:trust_basis],
        sensitivity: attrs[:sensitivity],
        candidate_state: "candidate"
      })
      |> Ash.create(authorize?: false, return_notifications?: true)
      |> unwrap_ash_result()
    end
  end

  def accept_evidence_candidate(session_context, operation, candidate, attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @evidence_accept_action),
         :ok <- validate_scope(session_context, candidate),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :evidence_accept,
             organization_id: session_context.organization_id
           ) do
      Repo.transaction(fn ->
        candidate = lock_candidate!(candidate.id)
        validate_scope!(session_context, candidate)

        verification_check =
          fetch_scoped!(VerificationCheck, session_context, candidate.verification_check_id)

        work_run = fetch_scoped!(Run, session_context, candidate.work_run_id)
        document = create_document!(session_context, operation, attrs[:body] || "")
        evidence_id = Ecto.UUID.generate()
        evidence_graph_item_id = Ecto.UUID.generate()
        now = DateTime.utc_now()

        graph_item =
          ash_create!(
            GraphItem,
            %{
              id: evidence_graph_item_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              resource_type: "evidence_item",
              resource_id: evidence_id,
              title: attrs[:title]
            }
          )

        evidence_item =
          ash_create!(
            EvidenceItem,
            %{
              id: evidence_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              graph_item_id: graph_item.id,
              verification_check_id: candidate.verification_check_id,
              artifact_id: candidate.artifact_id,
              body_document_id: document.id,
              candidate_id: candidate.id,
              work_run_id: candidate.work_run_id,
              accepted_by_principal_id: session_context.principal_id,
              acceptance_operation_id: operation.id,
              acceptance_policy_basis: attrs[:acceptance_policy_basis],
              accepted_at: now,
              visibility_constraints: Map.new(attrs[:visibility_constraints] || %{}),
              sensitivity: candidate.sensitivity,
              freshness_state: candidate.freshness_state,
              trust_basis: candidate.trust_basis,
              title: attrs[:title]
            }
          )

        verification_result =
          ash_create!(
            VerificationResult,
            %{
              id: Ecto.UUID.generate(),
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              verification_check_id: candidate.verification_check_id,
              evidence_item_id: evidence_item.id,
              operation_id: operation.id,
              work_run_id: work_run.id,
              work_packet_version_id: work_run.work_packet_version_id,
              target_graph_item_id: verification_check.graph_item_id,
              actor_principal_id: session_context.principal_id,
              policy_basis: attrs[:acceptance_policy_basis],
              reason: attrs[:reason],
              recorded_at: now,
              result: attrs[:result] || "passed"
            }
          )

        candidate =
          candidate
          |> Ash.Changeset.for_update(:mark_accepted, %{})
          |> Ash.update!(authorize?: false, return_notifications?: true)
          |> unwrap_notification_result()

        _required_check = update_required_check!(work_run.id, candidate.verification_check_id)
        work_run = update_work_run_after_acceptance!(work_run)

        %{
          evidence_item: evidence_item,
          verification_result: verification_result,
          evidence_graph_item: graph_item,
          candidate: candidate,
          work_run: work_run
        }
      end)
      |> normalize_transaction_result()
    end
  end

  defp validate_referenced_scope(session_context, attrs) do
    with :ok <-
           validate_scoped_reference(
             VerificationCheck,
             session_context,
             attrs[:verification_check_id]
           ),
         :ok <- validate_optional_scoped_reference(Run, session_context, attrs[:work_run_id]),
         :ok <-
           validate_optional_scoped_reference(
             ExecutionObservation,
             session_context,
             attrs[:execution_observation_id]
           ) do
      :ok
    end
  end

  defp validate_scoped_reference(resource, session_context, id) do
    case fetch_scoped(resource, session_context, id) do
      {:ok, _record} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp validate_optional_scoped_reference(_resource, _session_context, nil), do: :ok

  defp validate_optional_scoped_reference(resource, session_context, id) do
    validate_scoped_reference(resource, session_context, id)
  end

  defp fetch_scoped(resource, session_context, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:error, {:not_found, resource, id}}

      {:ok, record} ->
        case validate_scope(session_context, record) do
          :ok -> {:ok, record}
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp fetch_scoped!(resource, session_context, id) do
    case fetch_scoped(resource, session_context, id) do
      {:ok, record} -> record
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp lock_candidate!(id) do
    EvidenceCandidate
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> Repo.rollback({:not_found, EvidenceCandidate, id})
      {:ok, candidate} -> candidate
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update_required_check!(run_id, verification_check_id) do
    case Runs.mark_required_check_satisfied(run_id, verification_check_id) do
      {:ok, required_check} -> required_check
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update_work_run_after_acceptance!(work_run) do
    case Runs.set_run_verified(work_run) do
      {:ok, run} -> run
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp create_document!(session_context, operation, plain_text) do
    case Content.create_plain_document(session_context, operation, plain_text) do
      {:ok, document} -> document
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp validate_scope(session_context, record) do
    if record.organization_id == session_context.organization_id and
         record.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_scope!(session_context, record) do
    case validate_scope(session_context, record) do
      :ok -> :ok
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp validate_operation_context(session_context, operation)
       when is_map(session_context) and is_map(operation) do
    if operation.principal_id == session_context.principal_id and
         operation.session_id == session_context.session_id and
         operation.organization_id == session_context.organization_id and
         operation.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_operation_context(_session_context, _operation), do: {:error, :forbidden}

  defp validate_operation_action(operation, expected_action) do
    case operation.action do
      ^expected_action -> :ok
      _other -> {:error, {:invalid_operation_action, operation.id, expected_action}}
    end
  end

  defp ash_create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!(authorize?: false, return_notifications?: true)
    |> unwrap_notification_result()
  end

  defp unwrap_ash_result({:ok, record, _notifications}), do: {:ok, record}
  defp unwrap_ash_result({:ok, record}), do: {:ok, record}
  defp unwrap_ash_result({:error, error}), do: {:error, error}

  defp unwrap_notification_result({record, _notifications}), do: record
  defp unwrap_notification_result(record), do: record

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, error}), do: {:error, error}
end
