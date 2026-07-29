defmodule OfficeGraph.WorkGraph.VerificationCommands do
  @moduledoc false

  alias OfficeGraph.{Authorization, Operations}
  alias OfficeGraph.WorkGraph.CommandActionResult
  alias OfficeGraph.WorkGraph.CommandSupport, as: Support

  alias OfficeGraph.WorkGraph.{
    Artifact,
    EvidenceItem,
    RelationshipCommands,
    RelationshipRequest,
    ReviewFinding,
    Task,
    VerificationCheck,
    VerificationResult
  }

  require Ash.Query

  @verification_complete_action "verification.complete"
  @evidence_accept_action "evidence.accept"
  @direct_verification_policy_basis "verification_complete"

  @behaviour Ash.Resource.Actions.Implementation

  @impl true
  def run(input, [mode: :complete_verification], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @verification_complete_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :verification_complete,
             organization_id: session_context.organization_id
           ) do
      CommandActionResult.accepted(
        persist_completion!(
          session_context,
          operation,
          attrs.verification_check_id,
          Map.drop(attrs, [:operation_id, :verification_check_id])
        )
      )
    end
    |> normalize_run_result()
  end

  def run(input, [mode: :satisfy_from_evidence], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @evidence_accept_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :evidence_accept,
             organization_id: session_context.organization_id
           ) do
      CommandActionResult.accepted(
        persist_evidence_satisfaction!(
          session_context,
          operation,
          attrs.verification_check_id
        )
      )
    end
    |> normalize_run_result()
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def complete_verification(session_context, operation, verification_check, attrs) do
    VerificationCheck
    |> Ash.ActionInput.for_action(
      :persist_completion_contract,
      attrs
      |> Map.new()
      |> Map.put(:operation_id, operation.id)
      |> Map.put(:verification_check_id, verification_check.id)
    )
    |> Ash.run_action(actor: session_context, authorize?: false)
    |> normalize_contract_result()
    |> case do
      {:ok, changes} ->
        {:ok,
         %{
           artifact: changes.artifact,
           evidence_item: changes.evidence_item,
           verification_result: changes.verification_result,
           verification_check: changes.verification_check,
           review_finding: changes.review_finding,
           task: changes.task
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  def satisfy_verification_check_from_evidence(session_context, operation, verification_check) do
    VerificationCheck
    |> Ash.ActionInput.for_action(:persist_evidence_satisfaction_contract, %{
      operation_id: operation.id,
      verification_check_id: verification_check.id
    })
    |> Ash.run_action(actor: session_context, authorize?: false)
    |> normalize_contract_result()
  end

  defp persist_completion!(session_context, operation, verification_check_id, attrs) do
    artifact_id = Ecto.UUID.generate()
    artifact_graph_item_id = Ecto.UUID.generate()
    evidence_id = Ecto.UUID.generate()
    evidence_graph_item_id = Ecto.UUID.generate()
    verification_result_id = Ecto.UUID.generate()
    now = DateTime.utc_now()
    policy_basis = attrs[:policy_basis] || @direct_verification_policy_basis

    {verification_check, review_finding, task, task_review_findings, task_verification_checks} =
      lock_completion_graph!(session_context, verification_check_id)

    if verification_check.lifecycle_state != "required" do
      Support.rollback({:invalid_verification_check_status, verification_check.id})
    end

    Support.validate_open_review_finding!(review_finding)

    evidence_document =
      Support.create_document!(session_context, operation, attrs[:body] || "")

    artifact_graph_item =
      Support.create_graph_item!(
        artifact_graph_item_id,
        session_context,
        "artifact",
        artifact_id,
        attrs[:title]
      )

    artifact =
      Support.ash_create(
        Artifact,
        %{
          id: artifact_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          graph_item_id: artifact_graph_item_id,
          title: attrs[:title],
          uri: attrs[:artifact_uri]
        },
        session_context
      )
      |> Support.unwrap_ash()

    evidence_graph_item =
      Support.create_graph_item!(
        evidence_graph_item_id,
        session_context,
        "evidence_item",
        evidence_id,
        attrs[:title]
      )

    evidence_item =
      Support.ash_create(
        EvidenceItem,
        %{
          id: evidence_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          graph_item_id: evidence_graph_item_id,
          verification_check_id: verification_check.id,
          artifact_id: artifact.id,
          body_document_id: evidence_document.id,
          accepted_by_principal_id: session_context.principal_id,
          acceptance_operation_id: operation.id,
          acceptance_policy_basis: policy_basis,
          accepted_at: now,
          title: attrs[:title]
        },
        session_context
      )
      |> Support.unwrap_ash()

    check_evidence_relationship =
      create_relationship!(
        session_context,
        operation,
        verification_check.graph_item_id,
        evidence_graph_item_id,
        "evidenced_by"
      )

    evidence_artifact_relationship =
      create_relationship!(
        session_context,
        operation,
        evidence_graph_item_id,
        artifact_graph_item_id,
        "generated_from"
      )

    verification_result =
      Support.ash_create_internal(
        VerificationResult,
        %{
          id: verification_result_id,
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          verification_check_id: verification_check.id,
          evidence_item_id: evidence_item.id,
          operation_id: operation.id,
          target_graph_item_id: verification_check.graph_item_id,
          actor_principal_id: session_context.principal_id,
          policy_basis: policy_basis,
          reason: attrs[:reason],
          recorded_at: now,
          result: "passed"
        }
      )
      |> Support.unwrap_ash()

    verification_check =
      verification_check
      |> Support.ash_update_internal(:mark_satisfied)
      |> Support.unwrap_ash()

    {review_finding, task, completed_review_finding?, completed_task?} =
      maybe_complete_parent_work!(
        review_finding,
        task,
        task_review_findings,
        task_verification_checks,
        verification_check.id
      )

    Support.trace!(operation, "artifact.create", "artifact", artifact.id)
    Support.trace!(operation, "evidence_item.create", "evidence_item", evidence_item.id)

    Support.trace!(
      operation,
      "verification_result.create",
      "verification_result",
      verification_result.id
    )

    Support.trace!(
      operation,
      "verification_check.satisfy",
      "verification_check",
      verification_check.id
    )

    if completed_review_finding? do
      Support.trace!(
        operation,
        "review_finding.complete",
        "review_finding",
        review_finding.id
      )
    end

    if completed_task? do
      Support.trace!(operation, "task.complete", "task", task.id)
    end

    %{
      artifact_graph_item: artifact_graph_item,
      artifact: artifact,
      evidence_graph_item: evidence_graph_item,
      evidence_item: evidence_item,
      check_evidence_relationship: check_evidence_relationship,
      evidence_artifact_relationship: evidence_artifact_relationship,
      verification_result: verification_result,
      verification_check: verification_check,
      review_finding: review_finding,
      task: task
    }
  end

  defp persist_evidence_satisfaction!(session_context, operation, verification_check_id) do
    {verification_check, review_finding, task, task_review_findings, task_verification_checks} =
      lock_completion_graph!(session_context, verification_check_id)

    if verification_check.lifecycle_state != "required" do
      Support.rollback({:invalid_verification_check_status, verification_check.id})
    end

    Support.validate_open_review_finding!(review_finding)

    verification_check =
      verification_check
      |> Support.ash_update_internal(:mark_satisfied)
      |> Support.unwrap_ash()

    {review_finding, task, completed_review_finding?, completed_task?} =
      maybe_complete_parent_work!(
        review_finding,
        task,
        task_review_findings,
        task_verification_checks,
        verification_check.id
      )

    Support.trace!(
      operation,
      "verification_check.satisfy",
      "verification_check",
      verification_check.id
    )

    if completed_review_finding? do
      Support.trace!(
        operation,
        "review_finding.complete",
        "review_finding",
        review_finding.id
      )
    end

    if completed_task? do
      Support.trace!(operation, "task.complete", "task", task.id)
    end

    %{
      verification_check: verification_check,
      review_finding: review_finding,
      task: task
    }
  end

  defp normalize_contract_result(result) do
    result
    |> Support.normalize_action_result()
    |> case do
      {:ok, %CommandActionResult{} = action_result} ->
        CommandActionResult.to_public_result(action_result)

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_run_result({:ok, %CommandActionResult{}} = result), do: result
  defp normalize_run_result(%CommandActionResult{} = result), do: {:ok, result}

  defp normalize_run_result({:error, error}),
    do: CommandActionResult.rejected(error)

  def lock_verification_completion_scope(session_context, verification_check_id) do
    {verification_check, _review_finding, _task, _review_findings, _verification_checks} =
      lock_completion_graph!(session_context, verification_check_id)

    {:ok, verification_check}
  end

  defp lock_completion_graph!(session_context, verification_check_id) do
    verification_check_hint =
      VerificationCheck
      |> Support.ash_get(verification_check_id)
      |> Support.unwrap_ash()

    Support.validate_scope!(session_context, verification_check_hint)

    review_finding_hint =
      ReviewFinding
      |> Support.ash_get(verification_check_hint.review_finding_id)
      |> Support.unwrap_ash()

    Support.validate_scope!(session_context, review_finding_hint)

    task =
      Task
      |> Support.ash_get_for_update(review_finding_hint.task_id)
      |> Support.unwrap_ash()

    Support.validate_scope!(session_context, task)

    review_findings = lock_review_findings_for_task!(task.id)

    review_finding =
      Enum.find(review_findings, &(&1.id == review_finding_hint.id)) ||
        Support.rollback({:not_found, ReviewFinding, review_finding_hint.id})

    Support.validate_scope!(session_context, review_finding)

    verification_checks =
      review_findings
      |> Enum.map(& &1.id)
      |> lock_verification_checks_for_findings!()

    verification_check =
      Enum.find(verification_checks, &(&1.id == verification_check_hint.id)) ||
        Support.rollback({:not_found, VerificationCheck, verification_check_hint.id})

    Support.validate_scope!(session_context, verification_check)

    {verification_check, review_finding, task, review_findings, verification_checks}
  end

  defp lock_review_findings_for_task!(task_id) do
    ReviewFinding
    |> Ash.Query.filter(task_id == ^task_id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false)
  end

  defp lock_verification_checks_for_findings!([]), do: []

  defp lock_verification_checks_for_findings!(review_finding_ids) do
    VerificationCheck
    |> Ash.Query.filter(review_finding_id in ^review_finding_ids)
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false)
  end

  defp maybe_complete_parent_work!(
         review_finding,
         task,
         task_review_findings,
         task_verification_checks,
         satisfied_check_id
       ) do
    if required_verification_checks_remaining?(
         review_finding.id,
         task_verification_checks,
         satisfied_check_id
       ) do
      {review_finding, task, false, false}
    else
      review_finding =
        review_finding
        |> Support.ash_update_internal(:mark_verified_complete)
        |> Support.unwrap_ash()

      if review_findings_remaining?(task.id, task_review_findings, review_finding.id) do
        {review_finding, task, true, false}
      else
        task =
          task
          |> Support.ash_update_internal(:mark_verified_complete)
          |> Support.unwrap_ash()

        {review_finding, task, true, true}
      end
    end
  end

  defp required_verification_checks_remaining?(
         review_finding_id,
         task_verification_checks,
         satisfied_check_id
       ) do
    Enum.any?(task_verification_checks, fn check ->
      check.review_finding_id == review_finding_id and check.id != satisfied_check_id and
        check.lifecycle_state == "required"
    end)
  end

  defp review_findings_remaining?(task_id, task_review_findings, completed_review_finding_id) do
    Enum.any?(task_review_findings, fn finding ->
      finding.task_id == task_id and finding.id != completed_review_finding_id and
        finding.lifecycle_state != "verified_complete"
    end)
  end

  defp create_relationship!(
         session_context,
         operation,
         source_item_id,
         target_item_id,
         definition_key
       ) do
    request =
      RelationshipRequest.new!(%{
        definition_key: definition_key,
        source_item_id: source_item_id,
        target_item_id: target_item_id,
        workspace_id: session_context.workspace_id
      })

    session_context
    |> RelationshipCommands.create(operation, request)
    |> Support.unwrap_ash()
  end
end
