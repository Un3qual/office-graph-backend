defmodule OfficeGraph.Verification do
  @moduledoc """
  Public boundary for verification checks, evidence, and results.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Content,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Runs,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.Content
  alias OfficeGraph.Operations.OperationCorrelation
  alias OfficeGraph.Repo
  alias OfficeGraph.Runs
  alias OfficeGraph.WorkGraph

  alias OfficeGraph.Runs.{ExecutionObservation, Run}

  alias OfficeGraph.WorkGraph.{
    Artifact,
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
           ) do
      create_evidence_candidate_record(session_context, operation, attrs)
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
      case existing_acceptance_for_operation(session_context, operation) do
        {:ok, nil} ->
          accept_evidence_candidate_record(session_context, operation, candidate, attrs)

        {:ok, accepted} ->
          replay_acceptance_result(accepted, candidate)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def passed_evidence_input_acceptable?(attrs) when is_map(attrs) do
    attrs[:normalized_status] == "succeeded" and acceptable_evidence_source?(attrs)
  end

  defp create_evidence_candidate_record(session_context, operation, attrs) do
    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)

      case existing_candidate_for_operation(session_context, operation) do
        {:ok, nil} ->
          case validate_referenced_scope(session_context, attrs) do
            :ok -> create_evidence_candidate_record!(session_context, operation, attrs)
            {:error, error} -> Repo.rollback(error)
          end

        {:ok, candidate} ->
          candidate

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp create_evidence_candidate_record!(session_context, operation, attrs) do
    ash_create!(
      EvidenceCandidate,
      %{
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
      }
    )
  end

  defp accept_evidence_candidate_record(session_context, operation, candidate, attrs) do
    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)
      candidate = lock_candidate!(candidate.id)
      validate_scope!(session_context, candidate)

      case existing_acceptance_for_operation(session_context, operation) do
        {:ok, nil} ->
          accept_locked_candidate!(session_context, operation, candidate, attrs)

        {:ok, accepted} ->
          replay_acceptance_result!(accepted, candidate)

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp accept_locked_candidate!(session_context, operation, candidate, attrs) do
    verification_check =
      fetch_scoped!(VerificationCheck, session_context, candidate.verification_check_id)

    work_run = lock_optional_scoped!(Run, session_context, candidate.work_run_id)

    observation =
      validate_candidate_links!(session_context, candidate, work_run, verification_check)

    result = attrs[:result] || "passed"
    validate_runless_result_allowed!(work_run, candidate, result)
    validate_passed_result_allowed!(result, candidate, work_run, observation)

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
          work_run_id: candidate.work_run_id,
          work_packet_version_id: work_packet_version_id(work_run),
          target_graph_item_id: verification_check.graph_item_id,
          actor_principal_id: session_context.principal_id,
          policy_basis: attrs[:acceptance_policy_basis],
          reason: attrs[:reason],
          recorded_at: now,
          result: result
        }
      )

    candidate =
      candidate
      |> Ash.Changeset.for_update(:mark_accepted, %{})
      |> Ash.update!(authorize?: false, return_notifications?: true)
      |> unwrap_notification_result()

    work_run =
      update_after_acceptance!(
        session_context,
        operation,
        verification_check,
        work_run,
        verification_result
      )

    %{
      evidence_item: evidence_item,
      verification_result: verification_result,
      evidence_graph_item: graph_item,
      candidate: candidate,
      work_run: work_run
    }
  end

  defp validate_referenced_scope(session_context, attrs) do
    with {:ok, verification_check} <-
           fetch_scoped(
             VerificationCheck,
             session_context,
             attrs[:verification_check_id]
           ),
         {:ok, work_run} <- fetch_optional_scoped(Run, session_context, attrs[:work_run_id]),
         {:ok, observation} <-
           fetch_optional_scoped(
             ExecutionObservation,
             session_context,
             attrs[:execution_observation_id]
           ),
         {:ok, _artifact} <- fetch_optional_scoped(Artifact, session_context, attrs[:artifact_id]),
         :ok <- validate_run_requires_check(work_run, verification_check),
         :ok <- validate_observation_belongs(observation, work_run, verification_check) do
      :ok
    end
  end

  defp fetch_optional_scoped(_resource, _session_context, nil), do: {:ok, nil}

  defp fetch_optional_scoped(resource, session_context, id) do
    fetch_scoped(resource, session_context, id)
  end

  defp validate_run_requires_check(nil, _verification_check), do: :ok

  defp validate_run_requires_check(work_run, verification_check) do
    with {:ok, required_checks} <- Runs.required_checks_for_run(work_run.id) do
      if Enum.any?(required_checks, &(&1.verification_check_id == verification_check.id)) do
        :ok
      else
        {:error, {:verification_check_not_required, work_run.id, verification_check.id}}
      end
    end
  end

  defp validate_observation_belongs(nil, _work_run, _verification_check), do: :ok

  defp validate_observation_belongs(_observation, nil, _verification_check) do
    {:error, :missing_work_run_for_observation}
  end

  defp validate_observation_belongs(observation, work_run, verification_check) do
    if observation.work_run_id == work_run.id and
         observation.verification_check_id == verification_check.id do
      :ok
    else
      {:error, {:observation_not_for_candidate_run, observation.id}}
    end
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

  defp lock_scoped!(resource, session_context, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        Repo.rollback({:not_found, resource, id})

      {:ok, record} ->
        validate_scope!(session_context, record)
        record

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp lock_optional_scoped!(_resource, _session_context, nil), do: nil

  defp lock_optional_scoped!(resource, session_context, id) do
    lock_scoped!(resource, session_context, id)
  end

  defp validate_runless_result_allowed!(nil, _candidate, "passed"), do: :ok

  defp validate_runless_result_allowed!(nil, candidate, _result) do
    Repo.rollback({:runless_evidence_result_not_passed, candidate.id})
  end

  defp validate_runless_result_allowed!(_work_run, _candidate, _result), do: :ok

  defp validate_candidate_links!(session_context, candidate, work_run, verification_check) do
    with :ok <- validate_run_requires_check(work_run, verification_check),
         {:ok, observation} <-
           fetch_optional_scoped(
             ExecutionObservation,
             session_context,
             candidate.execution_observation_id
           ),
         :ok <- validate_observation_belongs(observation, work_run, verification_check) do
      observation
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp validate_passed_result_allowed!("passed", candidate, work_run, observation) do
    cond do
      not is_nil(observation) and observation.normalized_status != "succeeded" ->
        Repo.rollback({:observation_not_successful, observation.id})

      not is_nil(observation) and not acceptable_evidence_source?(observation) ->
        Repo.rollback({:observation_not_acceptable_evidence, observation.id})

      not acceptable_evidence_source?(candidate) ->
        Repo.rollback({:candidate_not_acceptable_evidence, candidate.id})

      work_run_failed?(work_run) ->
        Repo.rollback({:work_run_already_failed, work_run.id})

      true ->
        :ok
    end
  end

  defp validate_passed_result_allowed!(_result, _candidate, _work_run, _observation), do: :ok

  defp acceptable_evidence_source?(source) do
    Map.get(source, :freshness_state) == "fresh" and
      Map.get(source, :trust_basis) in ["owner_attested", "signed_provider_payload"]
  end

  defp work_run_failed?(nil), do: false

  defp work_run_failed?(work_run) do
    work_run.state == "failed" or work_run.aggregate_state == "failed" or
      work_run.execution_state == "failed" or work_run.verification_state == "failed"
  end

  defp update_after_acceptance!(
         session_context,
         operation,
         verification_check,
         nil,
         %{result: "passed"}
       ) do
    case WorkGraph.satisfy_verification_check_from_evidence(
           session_context,
           operation,
           verification_check
         ) do
      {:ok, _completed} -> nil
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update_after_acceptance!(_session_context, _operation, _verification_check, nil, _result) do
    nil
  end

  defp update_after_acceptance!(
         _session_context,
         _operation,
         _verification_check,
         work_run,
         %{result: "passed"} = verification_result
       ) do
    case Runs.satisfy_required_check_and_verify_run(
           work_run,
           verification_result.verification_check_id
         ) do
      {:ok, run} -> run
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update_after_acceptance!(
         _session_context,
         _operation,
         _verification_check,
         work_run,
         _verification_result
       ) do
    case Runs.set_run_verification_failed(work_run) do
      {:ok, run} -> run
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp work_packet_version_id(nil), do: nil
  defp work_packet_version_id(work_run), do: work_run.work_packet_version_id

  defp existing_candidate_for_operation(session_context, operation) do
    EvidenceCandidate
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        operation_id == ^operation.id
    )
    |> Ash.read_one(authorize?: false)
  end

  defp replay_acceptance_result(%{evidence_item: evidence_item} = accepted, candidate) do
    if evidence_item.candidate_id == candidate.id do
      {:ok, accepted}
    else
      {:error, {:evidence_acceptance_operation_conflict, evidence_item.id}}
    end
  end

  defp replay_acceptance_result!(accepted, candidate) do
    case replay_acceptance_result(accepted, candidate) do
      {:ok, accepted} -> accepted
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp existing_acceptance_for_operation(session_context, operation) do
    EvidenceItem
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        acceptance_operation_id == ^operation.id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, evidence_item} ->
        with {:ok, candidate} <-
               fetch_scoped(EvidenceCandidate, session_context, evidence_item.candidate_id),
             {:ok, graph_item} <-
               fetch_scoped(GraphItem, session_context, evidence_item.graph_item_id),
             {:ok, verification_result} <- read_verification_result_for_evidence(evidence_item.id),
             {:ok, work_run} <-
               fetch_optional_scoped(Run, session_context, evidence_item.work_run_id) do
          {:ok,
           %{
             evidence_item: evidence_item,
             verification_result: verification_result,
             evidence_graph_item: graph_item,
             candidate: candidate,
             work_run: work_run
           }}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp lock_operation!(operation_id) do
    OperationCorrelation
    |> Ash.Query.filter(id == ^operation_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> Repo.rollback({:not_found, OperationCorrelation, operation_id})
      {:ok, operation} -> operation
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp read_verification_result_for_evidence(evidence_item_id) do
    VerificationResult
    |> Ash.Query.filter(evidence_item_id == ^evidence_item_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, VerificationResult, evidence_item_id}}
      {:ok, verification_result} -> {:ok, verification_result}
      {:error, error} -> {:error, error}
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
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, record, notifications} -> unwrap_notification_result({record, notifications})
      {:ok, record} -> record
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp unwrap_notification_result({record, _notifications}), do: record
  defp unwrap_notification_result(record), do: record

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, error}), do: {:error, error}
end
