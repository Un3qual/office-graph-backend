defmodule OfficeGraph.Verification do
  @moduledoc """
  Public boundary for verification checks, evidence, and results.
  """

  use Boundary,
    deps: [
      OfficeGraph.Audit,
      OfficeGraph.Authorization,
      OfficeGraph.CommandSupport,
      OfficeGraph.Content,
      OfficeGraph.Operations,
      OfficeGraph.Revisions,
      OfficeGraph.Runs,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Authorization
  alias OfficeGraph.CommandSupport
  alias OfficeGraph.Content
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.Verification.CandidateActionResult
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
      trace!: 4,
      validate_scope: 2
    ]

  require Ash.Query

  @evidence_candidate_create_action "evidence_candidate.create"
  @evidence_accept_action "evidence.accept"
  @evidence_results ["passed", "failed"]

  @behaviour Ash.Resource.Actions.Implementation

  @impl true
  def run(input, [mode: :create_candidate], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    case Operations.lock_operation(attrs.operation_id) do
      {:ok, operation} ->
        case create_evidence_candidate_contract(
               session_context,
               operation,
               Map.delete(attrs, :operation_id)
             ) do
          {:ok, candidate} -> CandidateActionResult.candidate(candidate)
          {:rejected, error} -> CandidateActionResult.rejected(error)
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        CandidateActionResult.rejected(error)
    end
  end

  def run(input, [mode: :accept_candidate], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    case Operations.lock_operation(attrs.operation_id) do
      {:ok, operation} ->
        case accept_evidence_candidate_contract(
               session_context,
               operation,
               attrs.candidate_id,
               Map.drop(attrs, [:operation_id, :candidate_id])
             ) do
          {:ok, accepted} -> CandidateActionResult.accepted(accepted)
          {:rejected, error} -> CandidateActionResult.rejected(error)
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        CandidateActionResult.rejected(error)
    end
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def create_agent_evidence_candidate(operation, execution, context_package, step_key, summary) do
    with true <- is_binary(step_key) and is_binary(summary),
         :ok <- validate_agent_output(operation, execution, context_package, step_key),
         required_check when not is_nil(required_check) <-
           first_required_check(execution.run_id, execution.graph_item_id) do
      EvidenceCandidate
      |> Ash.Changeset.for_create(:create, %{
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
      |> Ash.create!(
        authorize?: false,
        return_notifications?: true,
        upsert?: true,
        upsert_identity: :unique_agent_step,
        upsert_fields: []
      )
      |> CommandSupport.record_without_notifications()
      |> validate_agent_candidate_replay(operation, context_package, summary)
    else
      false -> {:error, :invalid_agent_output}
      nil -> {:error, :required_verification_check_missing}
      {:error, _reason} = error -> error
    end
  end

  defp validate_agent_candidate_replay(candidate, operation, context_package, summary) do
    if candidate.operation_id == operation.id and
         candidate.context_package_id == context_package.id and candidate.claim == summary do
      candidate
    else
      {:error, :agent_evidence_candidate_replay_conflict}
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
      EvidenceCandidate
      |> Ash.ActionInput.for_action(
        :persist_candidate_contract,
        Map.put(attrs, :operation_id, operation.id)
      )
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> normalize_candidate_action_result()
      |> case do
        {:ok, %CandidateActionResult{} = result} ->
          CandidateActionResult.to_candidate_result(result)

        {:error, error} ->
          {:error, error}
      end
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
      EvidenceCandidate
      |> Ash.ActionInput.for_action(
        :accept_candidate_contract,
        attrs
        |> Map.put(:operation_id, operation.id)
        |> Map.put(:candidate_id, candidate.id)
      )
      |> Ash.run_action(actor: session_context, authorize?: false)
      |> normalize_candidate_action_result()
      |> case do
        {:ok, %CandidateActionResult{} = result} ->
          CandidateActionResult.to_acceptance_result(result)

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

  defp normalize_candidate_action_result(result) do
    case CommandSupport.normalize_action_result(result) do
      {:error, {:work_graph_action_error, error}} -> {:error, error}
      result -> result
    end
  end

  defp create_evidence_candidate_contract(session_context, operation, attrs) do
    case existing_candidate_for_operation(session_context, operation) do
      {:ok, nil} ->
        with :ok <- validate_referenced_scope(session_context, attrs) do
          create_evidence_candidate_record(session_context, operation, attrs)
        else
          {:error, error} -> {:rejected, error}
        end

      {:ok, candidate} ->
        replay_candidate(candidate, attrs)

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_evidence_candidate_record(session_context, operation, attrs) do
    EvidenceCandidate
    |> Ash.Changeset.for_create(:create, %{
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
    })
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> CommandSupport.normalize_ash_write()
  end

  defp accept_evidence_candidate_contract(
         session_context,
         operation,
         candidate_id,
         attrs
       ) do
    with {:ok, candidate} <- lock_candidate(candidate_id),
         :ok <- validate_scope(session_context, candidate) do
      case existing_acceptance_for_operation(session_context, operation) do
        {:ok, nil} ->
          with {:ok, acceptance} <-
                 prepare_candidate_acceptance(session_context, candidate, attrs) do
            persist_candidate_acceptance(session_context, operation, acceptance, attrs)
          end

        {:ok, accepted} ->
          case replay_acceptance_result(session_context, accepted, candidate, attrs) do
            {:ok, accepted} -> {:ok, accepted}
            {:error, error} -> {:rejected, error}
          end

        {:error, error} ->
          {:error, error}
      end
    else
      {:error, error} -> {:rejected, error}
    end
  end

  defp prepare_candidate_acceptance(session_context, candidate, attrs) do
    result = attrs[:result] || "passed"

    with :ok <- validate_candidate_acceptance_open(candidate),
         {:ok, work_run} <- lock_optional_scoped(Run, session_context, candidate.work_run_id),
         {:ok, verification_check} <-
           acceptance_verification_check(session_context, candidate, work_run),
         {:ok, artifact} <-
           lock_optional_scoped(Artifact, session_context, candidate.artifact_id),
         {:ok, observation} <-
           validate_candidate_links(session_context, candidate, work_run, verification_check),
         :ok <- validate_evidence_result(result),
         :ok <- preflight_result_slot(work_run, candidate.verification_check_id),
         :ok <- validate_work_run_acceptance_open(work_run),
         :ok <- validate_runless_result_allowed(work_run, candidate, result),
         :ok <- validate_passed_result_allowed(result, candidate, work_run, observation) do
      {:ok,
       %{
         artifact: artifact,
         candidate: candidate,
         result: result,
         verification_check: verification_check,
         work_run: work_run
       }}
    else
      {:error, error} -> {:rejected, error}
    end
  end

  defp acceptance_verification_check(session_context, candidate, nil) do
    WorkGraph.lock_verification_completion_scope(
      session_context,
      candidate.verification_check_id
    )
  end

  defp acceptance_verification_check(session_context, candidate, _work_run) do
    fetch_scoped(VerificationCheck, session_context, candidate.verification_check_id)
  end

  defp persist_candidate_acceptance(
         session_context,
         operation,
         acceptance,
         attrs
       ) do
    evidence_id = Ecto.UUID.generate()
    evidence_graph_item_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    with {:ok, _completed} <-
           prepare_runless_completion(
             session_context,
             operation,
             acceptance.verification_check,
             acceptance.work_run,
             acceptance.result
           ),
         {:ok, document} <-
           create_document(session_context, operation, attrs[:body] || ""),
         {:ok, graph_item} <-
           GraphItem
           |> Ash.Changeset.for_create(:create, %{
             id: evidence_graph_item_id,
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id,
             resource_type: "evidence_item",
             resource_id: evidence_id,
             title: attrs[:title]
           })
           |> Ash.create(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         {:ok, evidence_item} <-
           EvidenceItem
           |> Ash.Changeset.for_create(:create, %{
             id: evidence_id,
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id,
             graph_item_id: graph_item.id,
             verification_check_id: acceptance.candidate.verification_check_id,
             artifact_id: acceptance.candidate.artifact_id,
             body_document_id: document.id,
             candidate_id: acceptance.candidate.id,
             work_run_id: acceptance.candidate.work_run_id,
             accepted_by_principal_id: session_context.principal_id,
             acceptance_operation_id: operation.id,
             acceptance_policy_basis: attrs[:acceptance_policy_basis],
             accepted_at: now,
             sensitivity: acceptance.candidate.sensitivity,
             freshness_state: acceptance.candidate.freshness_state,
             trust_basis: acceptance.candidate.trust_basis,
             title: attrs[:title]
           })
           |> Ash.create(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         {:ok, _check_evidence_relationship} <-
           create_relationship(
             session_context,
             operation,
             acceptance.verification_check.graph_item_id,
             evidence_item.graph_item_id,
             "evidenced_by"
           ),
         {:ok, _evidence_artifact_relationship} <-
           maybe_create_evidence_artifact_relationship(
             session_context,
             operation,
             evidence_item,
             acceptance.artifact
           ),
         {:ok, verification_result} <-
           VerificationResult
           |> Ash.Changeset.for_create(:create, %{
             organization_id: session_context.organization_id,
             workspace_id: session_context.workspace_id,
             verification_check_id: acceptance.candidate.verification_check_id,
             evidence_item_id: evidence_item.id,
             operation_id: operation.id,
             work_run_id: acceptance.candidate.work_run_id,
             work_packet_version_id: work_packet_version_id(acceptance.work_run),
             target_graph_item_id: acceptance.verification_check.graph_item_id,
             actor_principal_id: session_context.principal_id,
             policy_basis: attrs[:acceptance_policy_basis],
             reason: attrs[:reason],
             recorded_at: now,
             result: acceptance.result
           })
           |> Ash.create(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         :ok <- trace_evidence_creation(operation, evidence_item, verification_result),
         {:ok, candidate} <-
           acceptance.candidate
           |> Ash.Changeset.for_update(:mark_accepted, %{})
           |> Ash.update(authorize?: false, return_notifications?: true)
           |> CommandSupport.normalize_ash_write(),
         :ok <- trace_candidate_acceptance(operation, candidate),
         {:ok, work_run} <-
           update_after_acceptance(
             session_context,
             operation,
             acceptance.verification_check,
             acceptance.work_run,
             verification_result
           ) do
      {:ok,
       %{
         evidence_item: evidence_item,
         verification_result: verification_result,
         evidence_graph_item: graph_item,
         candidate: candidate,
         work_run: work_run
       }}
    end
  end

  defp trace_evidence_creation(operation, evidence_item, verification_result) do
    trace!(operation, "evidence_item.create", "evidence_item", evidence_item.id)

    trace!(
      operation,
      "verification_result.create",
      "verification_result",
      verification_result.id
    )

    :ok
  end

  defp trace_candidate_acceptance(operation, candidate) do
    trace!(operation, "evidence_candidate.accept", "evidence_candidate", candidate.id)
    :ok
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

  defp lock_candidate(id) do
    EvidenceCandidate
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, EvidenceCandidate, id}}
      {:ok, candidate} -> {:ok, candidate}
      {:error, error} -> {:error, error}
    end
  end

  defp lock_optional_scoped(_resource, _session_context, nil), do: {:ok, nil}

  defp lock_optional_scoped(resource, session_context, id) do
    lock_scoped(resource, session_context, id)
  end

  defp lock_scoped(resource, session_context, id) do
    Operations.lock_scoped_target(resource, session_context, id)
  end

  defp validate_evidence_result(result) when result in @evidence_results, do: :ok

  defp validate_evidence_result(result), do: {:error, {:invalid_evidence_result, result}}

  defp validate_candidate_acceptance_open(%{candidate_state: "candidate"}), do: :ok

  defp validate_candidate_acceptance_open(%{candidate_state: "accepted"} = candidate) do
    {:error, {:evidence_candidate_already_accepted, candidate.id}}
  end

  defp validate_candidate_acceptance_open(candidate) do
    {:error, {:evidence_candidate_not_acceptable, candidate.id, candidate.candidate_state}}
  end

  defp validate_work_run_acceptance_open(nil), do: :ok

  defp validate_work_run_acceptance_open(work_run) do
    if work_run_verified?(work_run),
      do: {:error, {:work_run_already_verified, work_run.id}},
      else: :ok
  end

  defp validate_runless_result_allowed(nil, _candidate, "passed"), do: :ok

  defp validate_runless_result_allowed(nil, candidate, _result) do
    {:error, {:runless_evidence_result_not_passed, candidate.id}}
  end

  defp validate_runless_result_allowed(_work_run, _candidate, _result), do: :ok

  defp validate_candidate_links(session_context, candidate, work_run, verification_check) do
    with :ok <- validate_run_requires_check(work_run, verification_check),
         {:ok, observation} <-
           fetch_optional_scoped(
             ExecutionObservation,
             session_context,
             candidate.execution_observation_id
           ),
         :ok <- validate_observation_belongs(observation, work_run, verification_check) do
      {:ok, observation}
    end
  end

  defp validate_passed_result_allowed("passed", candidate, work_run, observation) do
    cond do
      not is_nil(observation) and observation.normalized_status != "succeeded" ->
        {:error, {:observation_not_successful, observation.id}}

      not is_nil(observation) and not acceptable_evidence_source?(observation) ->
        {:error, {:observation_not_acceptable_evidence, observation.id}}

      not acceptable_evidence_source?(candidate) ->
        {:error, {:candidate_not_acceptable_evidence, candidate.id}}

      work_run_failed?(work_run) ->
        {:error, {:work_run_already_failed, work_run.id}}

      true ->
        :ok
    end
  end

  defp validate_passed_result_allowed(_result, _candidate, _work_run, _observation), do: :ok

  defp work_run_failed?(nil), do: false

  defp work_run_failed?(work_run) do
    work_run.state == "failed" or work_run.aggregate_state == "failed" or
      work_run.execution_state == "failed" or work_run.verification_state == "failed"
  end

  defp work_run_verified?(work_run) do
    work_run.state == "verified" or work_run.aggregate_state == "verified" or
      work_run.verification_state == "verified"
  end

  defp preflight_result_slot(nil, _verification_check_id), do: :ok

  defp preflight_result_slot(work_run, verification_check_id) do
    VerificationResult
    |> Ash.Query.filter(
      work_run_id == ^work_run.id and verification_check_id == ^verification_check_id
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, existing_result} ->
        ResultSlotPolicy.preflight(existing_result, work_run.id, verification_check_id)

      {:error, error} ->
        {:error, error}
    end
  end

  defp prepare_runless_completion(
         session_context,
         operation,
         verification_check,
         nil,
         "passed"
       ) do
    WorkGraph.satisfy_verification_check_from_evidence(
      session_context,
      operation,
      verification_check
    )
  end

  defp prepare_runless_completion(
         _session_context,
         _operation,
         _verification_check,
         _work_run,
         _result
       ) do
    {:ok, nil}
  end

  defp update_after_acceptance(_session_context, _operation, _verification_check, nil, _result) do
    {:ok, nil}
  end

  defp update_after_acceptance(
         session_context,
         operation,
         verification_check,
         work_run,
         %{result: "passed"} = verification_result
       ) do
    with {:ok, _completed} <-
           WorkGraph.satisfy_verification_check_from_evidence(
             session_context,
             operation,
             verification_check
           ) do
      Runs.apply_accepted_verification_result(work_run, verification_result)
    end
  end

  defp update_after_acceptance(
         _session_context,
         _operation,
         _verification_check,
         work_run,
         verification_result
       ) do
    Runs.apply_accepted_verification_result(work_run, verification_result)
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

  defp replay_candidate(candidate, attrs) do
    if same_candidate_replay?(candidate, attrs) do
      {:ok, candidate}
    else
      {:rejected, {:evidence_candidate_operation_conflict, candidate.id}}
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

  defp create_document(session_context, operation, plain_text),
    do: Content.create_plain_document(session_context, operation, plain_text)

  defp maybe_create_evidence_artifact_relationship(
         _session_context,
         _operation,
         _evidence_item,
         nil
       ),
       do: {:ok, nil}

  defp maybe_create_evidence_artifact_relationship(
         session_context,
         operation,
         evidence_item,
         artifact
       ) do
    create_relationship(
      session_context,
      operation,
      evidence_item.graph_item_id,
      artifact.graph_item_id,
      "generated_from"
    )
  end

  defp create_relationship(
         session_context,
         operation,
         source_item_id,
         target_item_id,
         definition_key
       ) do
    WorkGraph.create_relationship(session_context, operation, %{
      definition_key: definition_key,
      source_item_id: source_item_id,
      target_item_id: target_item_id,
      workspace_id: session_context.workspace_id
    })
  end
end
