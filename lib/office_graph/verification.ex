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
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification.ResultSlotPolicy
  alias OfficeGraph.Verification.Waiver
  alias OfficeGraph.WorkGraph

  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}

  alias OfficeGraph.WorkGraph.{
    Artifact,
    EvidenceCandidate,
    EvidenceItem,
    GraphItem,
    ReviewFinding,
    VerificationCheck,
    VerificationResult
  }

  import OfficeGraph.Verification.CommandSupport,
    only: [
      fetch_optional_scoped: 3,
      fetch_scoped: 3,
      fetch_scoped!: 3,
      lock_operation!: 1,
      lock_optional_scoped!: 3,
      normalize_transaction_result: 1,
      trace!: 4,
      validate_scope: 2,
      validate_scope!: 2
    ]

  require Ash.Query

  @evidence_candidate_create_action "evidence_candidate.create"
  @evidence_accept_action "evidence.accept"
  @evidence_results ["passed", "failed"]

  def create_agent_evidence_candidate(operation, execution, context_package, step_key, summary) do
    with true <- is_binary(step_key) and is_binary(summary),
         :ok <- validate_agent_output(operation, execution, context_package, step_key),
         required_check when not is_nil(required_check) <-
           first_required_check(execution.run_id, execution.graph_item_id) do
      EvidenceCandidate
      |> Ash.Query.filter(execution_id == ^execution.id and step_key == ^step_key)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)
      |> case do
        nil ->
          Repo.ash_create!(EvidenceCandidate, %{
            id: Ecto.UUID.generate(),
            organization_id: execution.organization_id,
            workspace_id: execution.workspace_id,
            verification_check_id: required_check.verification_check_id,
            work_run_id: execution.run_id,
            operation_id: operation.id,
            execution_id: execution.id,
            context_package_id: context_package.id,
            step_key: step_key,
            claim: summary,
            source_kind: "agent_execution",
            source_identity: "#{execution.id}:#{step_key}",
            freshness_state: "fresh",
            trust_basis: "agent_reported",
            sensitivity: "internal"
          })

        candidate ->
          if candidate.operation_id == operation.id and
               candidate.context_package_id == context_package.id and candidate.claim == summary,
             do: candidate,
             else: Repo.rollback(:agent_evidence_candidate_replay_conflict)
      end
    else
      false -> {:error, :invalid_agent_output}
      nil -> {:error, :required_verification_check_missing}
      {:error, _reason} = error -> error
    end
  end

  defp first_required_check(run_id, graph_item_id) do
    RunRequiredCheck
    |> Ash.Query.filter(run_id == ^run_id and verification_check.graph_item_id == ^graph_item_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp validate_agent_output(operation, execution, context_package, step_key) do
    Operations.validate_agent_output_operation(operation, execution, context_package, step_key)
  end

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
    Waiver.execute(session_context, operation, run, required_check, attrs)
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
    preflight_result_slot!(work_run, candidate.verification_check_id)
    validate_work_run_acceptance_open!(work_run)
    validate_runless_result_allowed!(work_run, candidate, result)
    validate_passed_result_allowed!(result, candidate, work_run, observation)
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
        session_context,
        operation,
        verification_check.graph_item_id,
        evidence_item.graph_item_id,
        "evidenced_by"
      )

    _evidence_artifact_relationship =
      maybe_create_evidence_artifact_relationship!(
        session_context,
        operation,
        evidence_item,
        artifact
      )

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

  defp maybe_create_evidence_artifact_relationship!(
         _session_context,
         _operation,
         _evidence_item,
         nil
       ),
       do: nil

  defp maybe_create_evidence_artifact_relationship!(
         session_context,
         operation,
         evidence_item,
         artifact
       ) do
    create_relationship!(
      session_context,
      operation,
      evidence_item.graph_item_id,
      artifact.graph_item_id,
      "generated_from"
    )
  end

  defp create_relationship!(
         session_context,
         operation,
         source_item_id,
         target_item_id,
         definition_key
       ) do
    case WorkGraph.create_relationship(session_context, operation, %{
           definition_key: definition_key,
           source_item_id: source_item_id,
           target_item_id: target_item_id,
           workspace_id: session_context.workspace_id
         }) do
      {:ok, relationship} -> relationship
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp unwrap_notification_result({record, _notifications}), do: record
  defp unwrap_notification_result(record), do: record
end
