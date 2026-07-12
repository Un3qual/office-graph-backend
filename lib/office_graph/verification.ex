defmodule OfficeGraph.Verification do
  @moduledoc """
  Public boundary for verification checks, evidence, and results.
  """

  use Boundary,
    deps: [
      OfficeGraph.Audit,
      OfficeGraph.Authorization,
      OfficeGraph.Content,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Revisions,
      OfficeGraph.Runs,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.Content
  alias OfficeGraph.Operations
  alias OfficeGraph.Repo
  alias OfficeGraph.{Audit, Revisions}
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification.ResultSlotPolicy
  alias OfficeGraph.WorkGraph

  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}

  alias OfficeGraph.WorkGraph.{
    Artifact,
    EvidenceCandidate,
    EvidenceItem,
    GraphItem,
    GraphRelationship,
    ReviewFinding,
    VerificationCheck,
    VerificationResult
  }

  require Ash.Query

  @evidence_candidate_create_action "evidence_candidate.create"
  @evidence_accept_action "evidence.accept"
  @verification_waive_action "verification.waive"
  @evidence_results ["passed", "failed"]

  def get_candidate_for_accept_command(session_context, id) do
    Operations.read_command_target(
      EvidenceCandidate,
      :read_for_accept_command,
      session_context,
      id
    )
  end

  def get_run_for_waive_command(session_context, id) do
    Operations.read_command_target(Run, :read_for_waive_command, session_context, id)
  end

  def get_required_check_for_waive_command(session_context, id) do
    Operations.read_command_target(
      RunRequiredCheck,
      :read_for_waive_command,
      session_context,
      id
    )
  end

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
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @evidence_candidate_create_action),
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
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @evidence_accept_action),
         :ok <- validate_scope(session_context, candidate),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :evidence_accept,
             organization_id: session_context.organization_id
           ),
         {:ok, affected_refs} <-
           acceptance_affected_refs(session_context, candidate, attrs) do
      case existing_acceptance_for_operation(session_context, operation) do
        {:ok, nil} ->
          accept_evidence_candidate_record(session_context, operation, candidate, attrs)

        {:ok, accepted} ->
          replay_acceptance_result(session_context, accepted, candidate, attrs)

        {:error, error} ->
          {:error, error}
      end
      |> attach_acceptance_affected_refs(affected_refs)
    end
  end

  def waive_required_check(session_context, operation, run, required_check, attrs)
      when is_map(run) and is_map(required_check) and is_map(attrs) do
    command_input =
      attrs
      |> Map.put(:run_id, run.id)
      |> Map.put(:run_required_check_id, required_check.id)

    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, @verification_waive_action),
         :ok <- Operations.validate_command_replay(operation, command_input),
         :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             :verification_waive,
             organization_id: session_context.organization_id
           ),
         :ok <- validate_waiver_attrs(attrs) do
      waive_required_check_record(
        session_context,
        operation,
        %{run_id: run.id, required_check_id: required_check.id},
        attrs
      )
    end
  end

  def passed_evidence_input_acceptable?(attrs) when is_map(attrs) do
    attrs[:normalized_status] == "succeeded" and acceptable_evidence_source?(attrs)
  end

  def acceptable_evidence_source?(source) do
    Map.get(source, :freshness_state) == "fresh" and
      Map.get(source, :trust_basis) in ["owner_attested", "signed_provider_payload"]
  end

  defp acceptance_affected_refs(session_context, candidate, attrs) do
    case Map.get(attrs, :result, "passed") do
      "passed" ->
        passed_acceptance_affected_refs(session_context, candidate)

      _other ->
        {:ok,
         %{
           affected_verification_check_id: nil,
           affected_run_required_check_id: nil,
           affected_review_finding_id: nil,
           affected_task_id: nil
         }}
    end
  end

  defp passed_acceptance_affected_refs(session_context, candidate) do
    with {:ok, parent_refs} <- acceptance_parent_refs(session_context, candidate),
         {:ok, required_check_id} <- acceptance_required_check_id(session_context, candidate) do
      {:ok,
       Map.merge(parent_refs, %{
         affected_verification_check_id: candidate.verification_check_id,
         affected_run_required_check_id: required_check_id
       })}
    end
  end

  defp acceptance_parent_refs(session_context, candidate) do
    with {:ok, verification_check} <-
           fetch_scoped(VerificationCheck, session_context, candidate.verification_check_id),
         {:ok, review_finding} <-
           fetch_scoped(ReviewFinding, session_context, verification_check.review_finding_id) do
      {:ok,
       %{
         affected_review_finding_id: review_finding.id,
         affected_task_id: review_finding.task_id
       }}
    end
  end

  defp acceptance_required_check_id(_session_context, %{work_run_id: nil}), do: {:ok, nil}

  defp acceptance_required_check_id(session_context, candidate) do
    RunRequiredCheck
    |> Ash.Query.filter(
      run_id == ^candidate.work_run_id and
        verification_check_id == ^candidate.verification_check_id and
        organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.for_read(:read_for_accept_command)
    |> Ash.read_one(actor: session_context)
    |> case do
      {:ok, nil} ->
        {:error,
         {:not_found, RunRequiredCheck,
          %{
            run_id: candidate.work_run_id,
            verification_check_id: candidate.verification_check_id
          }}}

      {:ok, required_check} ->
        {:ok, required_check.id}

      {:error, error} ->
        {:error, error}
    end
  end

  defp attach_acceptance_affected_refs({:ok, accepted}, affected_refs) do
    {:ok, Map.merge(accepted, affected_refs)}
  end

  defp attach_acceptance_affected_refs(error, _affected_refs), do: error

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
          replay_candidate!(candidate, attrs)

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp waive_required_check_record(session_context, operation, target, attrs) do
    Repo.transaction(fn ->
      _operation = lock_operation!(operation.id)
      run = lock_scoped!(Run, session_context, target.run_id)
      required_checks = lock_run_required_checks!(run.id)

      case existing_waiver_for_operation(session_context, operation) do
        {:ok, nil} ->
          waive_locked_required_check!(
            session_context,
            operation,
            run,
            required_checks,
            target.required_check_id,
            attrs
          )

        {:ok, verification_result} ->
          replay_waiver!(run, required_checks, verification_result, target.required_check_id)

        {:error, error} ->
          Repo.rollback(error)
      end
    end)
    |> normalize_transaction_result()
  end

  defp waive_locked_required_check!(
         session_context,
         operation,
         run,
         required_checks,
         required_check_id,
         attrs
       ) do
    required_check = validate_pending_required_check!(run, required_checks, required_check_id)
    validate_expected_run_state!(run, attrs)

    case Runs.validate_required_check_contract(run, required_check) do
      :ok -> :ok
      {:error, error} -> Repo.rollback(error)
    end

    verification_check =
      fetch_scoped!(VerificationCheck, session_context, required_check.verification_check_id)

    verification_result =
      Repo.ash_create!(
        VerificationResult,
        %{
          id: Ecto.UUID.generate(),
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          verification_check_id: required_check.verification_check_id,
          evidence_item_id: nil,
          operation_id: operation.id,
          work_run_id: run.id,
          work_packet_version_id: run.work_packet_version_id,
          target_graph_item_id: verification_check.graph_item_id,
          actor_principal_id: session_context.principal_id,
          policy_basis: attrs[:policy_basis],
          reason: attrs[:reason],
          recorded_at: DateTime.utc_now(),
          result: "waived"
        }
      )

    %{run: updated_run, required_check: updated_required_check} =
      case Runs.apply_waived_verification_result(run, verification_result) do
        {:ok, result} -> result
        {:error, error} -> Repo.rollback(error)
      end

    trace!(
      operation,
      "verification_result.waive",
      "verification_result",
      verification_result.id
    )

    trace!(
      operation,
      "run_required_check.waive",
      "run_required_check",
      updated_required_check.id
    )

    %{
      verification_result: verification_result,
      required_check: updated_required_check,
      run: updated_run
    }
  end

  defp replay_waiver!(run, required_checks, verification_result, required_check_id) do
    required_check =
      Enum.find(required_checks, &(&1.id == required_check_id)) ||
        Repo.rollback({:run_required_check_mismatch, run.id, required_check_id})

    if verification_result.result == "waived" and
         verification_result.work_run_id == run.id and
         verification_result.verification_check_id == required_check.verification_check_id do
      %{
        verification_result: verification_result,
        required_check: required_check,
        run: run
      }
    else
      Repo.rollback({:verification_waiver_operation_conflict, verification_result.id})
    end
  end

  defp validate_pending_required_check!(run, required_checks, required_check_id) do
    case Enum.find(required_checks, &(&1.id == required_check_id)) do
      nil ->
        Repo.rollback({:run_required_check_mismatch, run.id, required_check_id})

      %{state: "pending"} = required_check ->
        required_check

      required_check ->
        Repo.rollback({:run_required_check_not_pending, required_check.id, required_check.state})
    end
  end

  defp validate_expected_run_state!(run, attrs) do
    if run.execution_state == attrs[:expected_execution_state] and
         run.verification_state == attrs[:expected_verification_state] do
      :ok
    else
      Repo.rollback({:stale_work_run_state, run.id, run.execution_state, run.verification_state})
    end
  end

  defp validate_waiver_attrs(attrs) do
    Enum.find_value([:reason, :policy_basis], :ok, fn field ->
      case attrs[field] do
        value when is_binary(value) ->
          if String.trim(value) == "", do: {:error, {:invalid_waiver_input, field}}

        _other ->
          {:error, {:invalid_waiver_input, field}}
      end
    end)
  end

  defp existing_waiver_for_operation(session_context, operation) do
    VerificationResult
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and operation_id == ^operation.id
    )
    |> Ash.read_one(authorize?: false)
  end

  defp lock_run_required_checks!(run_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.Query.sort(position: :asc, id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false)
  end

  defp create_evidence_candidate_record!(session_context, operation, attrs) do
    Repo.ash_create!(
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
        sensitivity: attrs[:sensitivity]
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
          validate_candidate_acceptance_open!(candidate)
          accept_locked_candidate!(session_context, operation, candidate, attrs)

        {:ok, accepted} ->
          replay_acceptance_result!(session_context, accepted, candidate, attrs)

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
    artifact = lock_optional_scoped!(Artifact, session_context, candidate.artifact_id)

    observation =
      validate_candidate_links!(session_context, candidate, work_run, verification_check)

    result = attrs[:result] || "passed"
    validate_evidence_result!(result)
    validate_work_run_acceptance_open!(work_run)
    validate_runless_result_allowed!(work_run, candidate, result)
    validate_passed_result_allowed!(result, candidate, work_run, observation)
    preflight_result_slot!(work_run, candidate.verification_check_id)
    prepare_runless_completion!(session_context, operation, verification_check, work_run, result)

    document = create_document!(session_context, operation, attrs[:body] || "")
    evidence_id = Ecto.UUID.generate()
    evidence_graph_item_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    graph_item =
      Repo.ash_create!(
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
      Repo.ash_create!(
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

    _check_evidence_relationship =
      create_relationship!(
        verification_check.graph_item_id,
        evidence_item.graph_item_id,
        "has_evidence"
      )

    _evidence_artifact_relationship =
      maybe_create_evidence_artifact_relationship!(evidence_item, artifact)

    verification_result =
      Repo.ash_create!(
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

    trace!(operation, "evidence_item.create", "evidence_item", evidence_item.id)

    trace!(
      operation,
      "verification_result.create",
      "verification_result",
      verification_result.id
    )

    candidate =
      candidate
      |> Ash.Changeset.for_update(:mark_accepted, %{})
      |> Ash.update!(authorize?: false, return_notifications?: true)
      |> unwrap_notification_result()

    trace!(operation, "evidence_candidate.accept", "evidence_candidate", candidate.id)

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
    if observation_matches_candidate_check?(observation, work_run, verification_check) do
      :ok
    else
      {:error, {:observation_not_for_candidate_run, observation.id}}
    end
  end

  defp observation_matches_candidate_check?(observation, work_run, verification_check) do
    observation.work_run_id == work_run.id and
      (observation.verification_check_id == verification_check.id or
         (is_nil(observation.verification_check_id) and
            observation.graph_item_id == verification_check.graph_item_id))
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

  defp validate_evidence_result!(result) when result in @evidence_results, do: :ok

  defp validate_evidence_result!(result) do
    Repo.rollback({:invalid_evidence_result, result})
  end

  defp validate_candidate_acceptance_open!(%{candidate_state: "candidate"}), do: :ok

  defp validate_candidate_acceptance_open!(%{candidate_state: "accepted"} = candidate) do
    Repo.rollback({:evidence_candidate_already_accepted, candidate.id})
  end

  defp validate_candidate_acceptance_open!(candidate) do
    Repo.rollback({:evidence_candidate_not_acceptable, candidate.id, candidate.candidate_state})
  end

  defp validate_work_run_acceptance_open!(nil), do: :ok

  defp validate_work_run_acceptance_open!(work_run) do
    if work_run_verified?(work_run) do
      Repo.rollback({:work_run_already_verified, work_run.id})
    else
      :ok
    end
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

  defp work_run_failed?(nil), do: false

  defp work_run_failed?(work_run) do
    work_run.state == "failed" or work_run.aggregate_state == "failed" or
      work_run.execution_state == "failed" or work_run.verification_state == "failed"
  end

  defp work_run_verified?(work_run) do
    work_run.state == "verified" or work_run.aggregate_state == "verified" or
      work_run.verification_state == "verified"
  end

  defp preflight_result_slot!(nil, _verification_check_id), do: :ok

  defp preflight_result_slot!(work_run, verification_check_id) do
    existing_result =
      VerificationResult
      |> Ash.Query.filter(
        work_run_id == ^work_run.id and verification_check_id == ^verification_check_id
      )
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    case ResultSlotPolicy.preflight(existing_result, work_run.id, verification_check_id) do
      :ok -> :ok
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp prepare_runless_completion!(
         session_context,
         operation,
         verification_check,
         nil,
         "passed"
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

  defp prepare_runless_completion!(
         _session_context,
         _operation,
         _verification_check,
         _work_run,
         _result
       ) do
    :ok
  end

  defp update_after_acceptance!(_session_context, _operation, _verification_check, nil, _result) do
    nil
  end

  defp update_after_acceptance!(
         session_context,
         operation,
         verification_check,
         work_run,
         %{result: "passed"} = verification_result
       ) do
    case WorkGraph.satisfy_verification_check_from_evidence(
           session_context,
           operation,
           verification_check
         ) do
      {:ok, _completed} -> apply_accepted_verification_result!(work_run, verification_result)
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update_after_acceptance!(
         _session_context,
         _operation,
         _verification_check,
         work_run,
         verification_result
       ) do
    apply_accepted_verification_result!(work_run, verification_result)
  end

  defp apply_accepted_verification_result!(work_run, verification_result) do
    case Runs.apply_accepted_verification_result(work_run, verification_result) do
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

  defp replay_candidate!(candidate, attrs) do
    if same_candidate_replay?(candidate, attrs) do
      candidate
    else
      Repo.rollback({:evidence_candidate_operation_conflict, candidate.id})
    end
  end

  defp same_candidate_replay?(candidate, attrs) do
    candidate.verification_check_id == attrs[:verification_check_id] and
      candidate.work_run_id == attrs[:work_run_id] and
      candidate.execution_observation_id == attrs[:execution_observation_id] and
      candidate.artifact_id == attrs[:artifact_id] and candidate.claim == attrs[:claim] and
      candidate.source_kind == attrs[:source_kind] and
      candidate.source_identity == attrs[:source_identity] and
      candidate.freshness_state == attrs[:freshness_state] and
      candidate.trust_basis == attrs[:trust_basis] and
      candidate.sensitivity == attrs[:sensitivity]
  end

  defp replay_acceptance_result(%{evidence_item: evidence_item} = accepted, candidate) do
    if evidence_item.candidate_id == candidate.id do
      {:ok, accepted}
    else
      {:error, {:evidence_acceptance_operation_conflict, evidence_item.id}}
    end
  end

  defp replay_acceptance_result!(session_context, accepted, candidate, attrs) do
    case replay_acceptance_result(session_context, accepted, candidate, attrs) do
      {:ok, accepted} -> accepted
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp replay_acceptance_result(session_context, accepted, candidate, attrs) do
    with {:ok, accepted} <- replay_acceptance_result(accepted, candidate),
         :ok <- validate_acceptance_replay(session_context, accepted, attrs) do
      {:ok, accepted}
    end
  end

  defp validate_acceptance_replay(session_context, accepted, attrs) do
    evidence_item = accepted.evidence_item
    verification_result = accepted.verification_result

    with {:ok, body} <-
           Content.plain_text_for_document(session_context, evidence_item.body_document_id) do
      if same_acceptance_replay?(evidence_item, verification_result, body, attrs) do
        :ok
      else
        {:error, {:evidence_acceptance_operation_conflict, evidence_item.id}}
      end
    end
  end

  defp same_acceptance_replay?(evidence_item, verification_result, body, attrs) do
    evidence_item.title == attrs[:title] and
      evidence_item.acceptance_policy_basis == attrs[:acceptance_policy_basis] and
      evidence_item.visibility_constraints == Map.new(attrs[:visibility_constraints] || %{}) and
      body == (attrs[:body] || "") and verification_result.result == (attrs[:result] || "passed") and
      verification_result.policy_basis == attrs[:acceptance_policy_basis] and
      verification_result.reason == attrs[:reason]
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
    case Operations.lock_operation(operation_id) do
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

  defp maybe_create_evidence_artifact_relationship!(_evidence_item, nil), do: nil

  defp maybe_create_evidence_artifact_relationship!(evidence_item, artifact) do
    create_relationship!(
      evidence_item.graph_item_id,
      artifact.graph_item_id,
      "references_artifact"
    )
  end

  defp create_relationship!(source_item_id, target_item_id, relationship_type) do
    Repo.ash_create!(
      GraphRelationship,
      %{
        id: Ecto.UUID.generate(),
        source_item_id: source_item_id,
        target_item_id: target_item_id,
        relationship_type: relationship_type
      }
    )
  end

  defp trace!(operation, action, resource_type, resource_id) do
    Audit.record!(operation, action, resource_type, resource_id)
    Revisions.record!(operation, resource_type, resource_id, action, action)
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

  defp unwrap_notification_result({record, _notifications}), do: record
  defp unwrap_notification_result(record), do: record

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, error}), do: {:error, error}
end
