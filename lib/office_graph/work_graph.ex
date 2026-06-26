defmodule OfficeGraph.WorkGraph do
  @moduledoc """
  Public boundary for graph items, typed relationships, and graph reads.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Audit,
      OfficeGraph.Content,
      OfficeGraph.Operations,
      OfficeGraph.Repo,
      OfficeGraph.Revisions
    ],
    exports: []

  alias OfficeGraph.Audit
  alias OfficeGraph.Authorization
  alias OfficeGraph.Content
  alias OfficeGraph.Repo
  alias OfficeGraph.Revisions

  require Ash.Query

  alias OfficeGraph.WorkGraph.{
    Artifact,
    EvidenceItem,
    GraphItem,
    GraphRelationship,
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck,
    VerificationResult
  }

  @proposed_change_apply_action "proposed_change.apply"
  @verification_complete_action "verification.complete"
  @evidence_accept_action "evidence.accept"
  @direct_verification_policy_basis "verification_complete"

  def get_verification_check(session_context, id) do
    VerificationCheck
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(actor: session_context)
    |> case do
      {:ok, nil} -> {:error, {:missing_verification_check, id}}
      {:ok, verification_check} -> {:ok, verification_check}
      {:error, _error} -> {:error, {:missing_verification_check, id}}
    end
  end

  def create_signal(session_context, operation, attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @proposed_change_apply_action),
         :ok <- authorize_signal_create(session_context, operation) do
      signal_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      graph_transaction(fn ->
        document = create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          create_graph_item!(
            graph_item_id,
            session_context,
            "signal",
            signal_id,
            attrs[:title]
          )

        signal =
          ash_create(
            Signal,
            %{
              id: signal_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              graph_item_id: graph_item_id,
              body_document_id: document.id,
              title: attrs[:title]
            },
            session_context
          )
          |> unwrap_ash()

        trace!(operation, "signal.create", "signal", signal.id)

        %{document: document, graph_item: graph_item, signal: signal}
      end)
      |> case do
        {:ok, %{document: document, graph_item: graph_item, signal: signal}} ->
          {:ok, %{graph_item: graph_item, signal: signal, document: document}}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def create_task(session_context, operation, signal, attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @proposed_change_apply_action) do
      task_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      graph_transaction(fn ->
        document = create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          create_graph_item!(graph_item_id, session_context, "task", task_id, attrs[:title])

        task =
          ash_create(
            Task,
            %{
              id: task_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              graph_item_id: graph_item_id,
              source_signal_id: signal.id,
              body_document_id: document.id,
              title: attrs[:title]
            },
            session_context
          )
          |> unwrap_ash()

        source_signal_graph_item_id = persisted_graph_item_id!(Signal, signal.id)

        relationship =
          create_relationship!(
            source_signal_graph_item_id,
            graph_item_id,
            "produced_task",
            session_context
          )

        trace!(operation, "task.create", "task", task.id)

        %{graph_item: graph_item, task: task, relationship: relationship}
      end)
      |> transaction_result(:task, operation, "task.create", "task")
    end
  end

  def create_review_finding(session_context, operation, task, attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @proposed_change_apply_action) do
      finding_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      graph_transaction(fn ->
        task =
          Task
          |> ash_get_for_update(task.id)
          |> unwrap_ash()

        validate_scope!(session_context, task)
        validate_open_task!(task)

        document = create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          create_graph_item!(
            graph_item_id,
            session_context,
            "review_finding",
            finding_id,
            attrs[:title]
          )

        review_finding =
          ash_create(
            ReviewFinding,
            %{
              id: finding_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              graph_item_id: graph_item_id,
              task_id: task.id,
              body_document_id: document.id,
              title: attrs[:title]
            },
            session_context
          )
          |> unwrap_ash()

        relationship =
          create_relationship!(
            task.graph_item_id,
            graph_item_id,
            "has_review_finding",
            session_context
          )

        trace!(operation, "review_finding.create", "review_finding", review_finding.id)

        %{graph_item: graph_item, review_finding: review_finding, relationship: relationship}
      end)
      |> transaction_result(
        :review_finding,
        operation,
        "review_finding.create",
        "review_finding"
      )
    end
  end

  def create_verification_check(session_context, operation, review_finding, attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @proposed_change_apply_action) do
      check_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      graph_transaction(fn ->
        review_finding =
          ReviewFinding
          |> ash_get_for_update(review_finding.id)
          |> unwrap_ash()

        validate_scope!(session_context, review_finding)
        validate_open_review_finding!(review_finding)

        document = create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          create_graph_item!(
            graph_item_id,
            session_context,
            "verification_check",
            check_id,
            attrs[:title]
          )

        verification_check =
          ash_create(
            VerificationCheck,
            %{
              id: check_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              graph_item_id: graph_item_id,
              review_finding_id: review_finding.id,
              description_document_id: document.id,
              title: attrs[:title]
            },
            session_context
          )
          |> unwrap_ash()

        relationship =
          create_relationship!(
            review_finding.graph_item_id,
            graph_item_id,
            "requires_verification",
            session_context
          )

        trace!(
          operation,
          "verification_check.create",
          "verification_check",
          verification_check.id
        )

        %{
          graph_item: graph_item,
          verification_check: verification_check,
          relationship: relationship
        }
      end)
      |> transaction_result(
        :verification_check,
        operation,
        "verification_check.create",
        "verification_check"
      )
    end
  end

  def complete_verification(session_context, operation, verification_check, attrs) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @verification_complete_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :verification_complete,
             organization_id: session_context.organization_id
           ) do
      artifact_id = Ecto.UUID.generate()
      artifact_graph_item_id = Ecto.UUID.generate()
      evidence_id = Ecto.UUID.generate()
      evidence_graph_item_id = Ecto.UUID.generate()
      verification_result_id = Ecto.UUID.generate()
      now = DateTime.utc_now()
      policy_basis = attrs[:policy_basis] || @direct_verification_policy_basis

      graph_transaction(fn ->
        {verification_check, review_finding, task, task_review_findings, task_verification_checks} =
          lock_completion_graph!(session_context, verification_check.id)

        if verification_check.lifecycle_state != "required" do
          Repo.rollback({:invalid_verification_check_status, verification_check.id})
        end

        validate_open_review_finding!(review_finding)

        evidence_document = create_document!(session_context, operation, attrs[:body] || "")

        artifact_graph_item =
          create_graph_item!(
            artifact_graph_item_id,
            session_context,
            "artifact",
            artifact_id,
            attrs[:title]
          )

        artifact =
          ash_create(
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
          |> unwrap_ash()

        evidence_graph_item =
          create_graph_item!(
            evidence_graph_item_id,
            session_context,
            "evidence_item",
            evidence_id,
            attrs[:title]
          )

        evidence_item =
          ash_create(
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
          |> unwrap_ash()

        check_evidence_relationship =
          create_relationship!(
            verification_check.graph_item_id,
            evidence_graph_item_id,
            "has_evidence",
            session_context
          )

        evidence_artifact_relationship =
          create_relationship!(
            evidence_graph_item_id,
            artifact_graph_item_id,
            "references_artifact",
            session_context
          )

        verification_result =
          ash_create_internal(
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
          |> unwrap_ash()

        verification_check =
          verification_check
          |> ash_update_internal(:mark_satisfied)
          |> unwrap_ash()

        {review_finding, task, completed_review_finding?, completed_task?} =
          maybe_complete_parent_work!(
            review_finding,
            task,
            task_review_findings,
            task_verification_checks,
            verification_check.id
          )

        trace!(operation, "artifact.create", "artifact", artifact.id)
        trace!(operation, "evidence_item.create", "evidence_item", evidence_item.id)

        trace!(
          operation,
          "verification_result.create",
          "verification_result",
          verification_result.id
        )

        trace!(
          operation,
          "verification_check.satisfy",
          "verification_check",
          verification_check.id
        )

        if completed_review_finding? do
          trace!(
            operation,
            "review_finding.complete",
            "review_finding",
            review_finding.id
          )
        end

        if completed_task? do
          trace!(operation, "task.complete", "task", task.id)
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
      end)
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
  end

  def satisfy_verification_check_from_evidence(session_context, operation, verification_check) do
    with :ok <- validate_operation_context(session_context, operation),
         :ok <- validate_operation_action(operation, @evidence_accept_action),
         :ok <-
           Authorization.authorize_operation(session_context, operation, :evidence_accept,
             organization_id: session_context.organization_id
           ) do
      graph_transaction(fn ->
        {verification_check, review_finding, task, task_review_findings, task_verification_checks} =
          lock_completion_graph!(session_context, verification_check.id)

        if verification_check.lifecycle_state != "required" do
          Repo.rollback({:invalid_verification_check_status, verification_check.id})
        end

        validate_open_review_finding!(review_finding)

        verification_check =
          verification_check
          |> ash_update_internal(:mark_satisfied)
          |> unwrap_ash()

        {review_finding, task, completed_review_finding?, completed_task?} =
          maybe_complete_parent_work!(
            review_finding,
            task,
            task_review_findings,
            task_verification_checks,
            verification_check.id
          )

        trace!(
          operation,
          "verification_check.satisfy",
          "verification_check",
          verification_check.id
        )

        if completed_review_finding? do
          trace!(
            operation,
            "review_finding.complete",
            "review_finding",
            review_finding.id
          )
        end

        if completed_task? do
          trace!(operation, "task.complete", "task", task.id)
        end

        %{
          verification_check: verification_check,
          review_finding: review_finding,
          task: task
        }
      end)
    end
  end

  defp transaction_result({:ok, changes}, key, operation, action, resource_type) do
    resource = Map.fetch!(changes, key)
    _ = {operation, action, resource_type, resource}
    {:ok, Map.take(changes, [:graph_item, key, :relationship])}
  end

  defp transaction_result({:error, changeset}, _key, _operation, _action, _resource_type) do
    {:error, changeset}
  end

  defp graph_transaction(fun) do
    Repo.transaction(fun)
  end

  defp create_document!(session_context, operation, plain_text) do
    session_context
    |> Content.create_plain_document(operation, plain_text)
    |> unwrap_content()
  end

  # WorkGraph wraps Ash calls in graph transactions; request notifications so Ash
  # does not warn about missed dispatch, then ignore them until real notifiers exist.
  defp ash_create(resource, attrs, session_context) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, actor: session_context)
    |> Ash.create(authorize?: true, return_notifications?: true)
    |> unwrap_ash_result()
  end

  defp ash_create_internal(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> unwrap_ash_result()
  end

  defp ash_update_internal(record, action) do
    record
    |> Ash.Changeset.for_update(action, %{})
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> unwrap_ash_result()
  end

  defp ash_get(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, resource, id}}
      result -> result
    end
  end

  defp ash_get_for_update(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:not_found, resource, id}}
      result -> result
    end
  end

  defp unwrap_ash_result({:ok, record}) do
    {:ok, record}
  end

  defp unwrap_ash_result({:ok, record, _notifications}) do
    {:ok, record}
  end

  defp unwrap_ash_result({:error, error}) do
    {:error, error}
  end

  defp unwrap_ash({:ok, record}) do
    record
  end

  defp unwrap_ash({:error, error}) do
    Repo.rollback(error)
  end

  defp unwrap_content({:ok, document}) do
    document
  end

  defp unwrap_content({:error, error}) do
    Repo.rollback(error)
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

  defp validate_open_task!(%{lifecycle_state: "open"}), do: :ok

  defp validate_open_task!(task) do
    Repo.rollback({:invalid_task_status, task.id})
  end

  defp validate_open_review_finding!(%{lifecycle_state: "open"}), do: :ok

  defp validate_open_review_finding!(review_finding) do
    Repo.rollback({:invalid_review_finding_status, review_finding.id})
  end

  defp authorize_signal_create(session_context, operation) do
    Authorization.authorize_operation(session_context, operation, :proposed_change_apply,
      organization_id: session_context.organization_id
    )
  end

  defp create_graph_item!(id, session_context, resource_type, resource_id, title) do
    ash_create_internal(
      GraphItem,
      %{
        id: id,
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        resource_type: resource_type,
        resource_id: resource_id,
        title: title
      }
    )
    |> unwrap_ash()
  end

  defp create_relationship!(source_item_id, target_item_id, relationship_type, _session_context) do
    ash_create_internal(
      GraphRelationship,
      %{
        id: Ecto.UUID.generate(),
        source_item_id: source_item_id,
        target_item_id: target_item_id,
        relationship_type: relationship_type
      }
    )
    |> unwrap_ash()
  end

  defp persisted_graph_item_id!(resource, id) do
    resource
    |> ash_get_for_update(id)
    |> unwrap_ash()
    |> Map.fetch!(:graph_item_id)
  end

  defp lock_completion_graph!(session_context, verification_check_id) do
    verification_check_hint =
      VerificationCheck
      |> ash_get(verification_check_id)
      |> unwrap_ash()

    validate_scope!(session_context, verification_check_hint)

    review_finding_hint =
      ReviewFinding
      |> ash_get(verification_check_hint.review_finding_id)
      |> unwrap_ash()

    validate_scope!(session_context, review_finding_hint)

    task =
      Task
      |> ash_get_for_update(review_finding_hint.task_id)
      |> unwrap_ash()

    validate_scope!(session_context, task)

    review_findings = lock_review_findings_for_task!(task.id)

    review_finding =
      Enum.find(review_findings, &(&1.id == review_finding_hint.id)) ||
        Repo.rollback({:not_found, ReviewFinding, review_finding_hint.id})

    validate_scope!(session_context, review_finding)

    verification_checks =
      review_findings
      |> Enum.map(& &1.id)
      |> lock_verification_checks_for_findings!()

    verification_check =
      Enum.find(verification_checks, &(&1.id == verification_check_hint.id)) ||
        Repo.rollback({:not_found, VerificationCheck, verification_check_hint.id})

    validate_scope!(session_context, verification_check)

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
        |> ash_update_internal(:mark_verified_complete)
        |> unwrap_ash()

      if review_findings_remaining?(task.id, task_review_findings, review_finding.id) do
        {review_finding, task, true, false}
      else
        task =
          task
          |> ash_update_internal(:mark_verified_complete)
          |> unwrap_ash()

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

  defp trace!(operation, action, resource_type, resource_id) do
    Audit.record!(operation, action, resource_type, resource_id)
    Revisions.record!(operation, resource_type, resource_id, action, action)
  end
end
