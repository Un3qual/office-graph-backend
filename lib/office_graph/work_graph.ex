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

  def get_verification_check!(id), do: Ash.get!(VerificationCheck, id, authorize?: false)

  def create_signal(session_context, operation, attrs) do
    with :ok <-
           Authorization.authorize(session_context, :manual_intake_submit,
             organization_id: session_context.organization_id
           ) do
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
              title: attrs[:title],
              state: "open"
            },
            session_context
          )
          |> unwrap_ash()

        %{document: document, graph_item: graph_item, signal: signal}
      end)
      |> case do
        {:ok, %{document: document, graph_item: graph_item, signal: signal}} ->
          trace!(operation, "signal.create", "signal", signal.id)
          {:ok, %{graph_item: graph_item, signal: signal, document: document}}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def create_task(session_context, operation, signal, attrs) do
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
            title: attrs[:title],
            lifecycle_state: "open"
          },
          session_context
        )
        |> unwrap_ash()

      relationship =
        create_relationship!(
          signal.graph_item_id,
          graph_item_id,
          "produced_task",
          session_context
        )

      %{graph_item: graph_item, task: task, relationship: relationship}
    end)
    |> transaction_result(:task, operation, "task.create", "task")
  end

  def create_review_finding(session_context, operation, task, attrs) do
    finding_id = Ecto.UUID.generate()
    graph_item_id = Ecto.UUID.generate()

    graph_transaction(fn ->
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
            title: attrs[:title],
            lifecycle_state: "open"
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

      %{graph_item: graph_item, review_finding: review_finding, relationship: relationship}
    end)
    |> transaction_result(
      :review_finding,
      operation,
      "review_finding.create",
      "review_finding"
    )
  end

  def create_verification_check(session_context, operation, review_finding, attrs) do
    check_id = Ecto.UUID.generate()
    graph_item_id = Ecto.UUID.generate()

    graph_transaction(fn ->
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
            title: attrs[:title],
            lifecycle_state: "required"
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

  def complete_verification(session_context, operation, verification_check, attrs) do
    with {:ok, review_finding} <- ash_get(ReviewFinding, verification_check.review_finding_id),
         {:ok, task} <- ash_get(Task, review_finding.task_id) do
      artifact_id = Ecto.UUID.generate()
      artifact_graph_item_id = Ecto.UUID.generate()
      evidence_id = Ecto.UUID.generate()
      evidence_graph_item_id = Ecto.UUID.generate()
      verification_result_id = Ecto.UUID.generate()

      graph_transaction(fn ->
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
              title: attrs[:title],
              state: "accepted"
            },
            session_context
          )
          |> unwrap_ash()

        verification_result =
          ash_create(
            VerificationResult,
            %{
              id: verification_result_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              verification_check_id: verification_check.id,
              evidence_item_id: evidence_item.id,
              operation_id: operation.id,
              result: "passed"
            },
            session_context
          )
          |> unwrap_ash()

        verification_check =
          VerificationCheck
          |> ash_get_for_update(verification_check.id)
          |> unwrap_ash()
          |> ash_update(:mark_satisfied, session_context)
          |> unwrap_ash()

        review_finding =
          ReviewFinding
          |> ash_get_for_update(review_finding.id)
          |> unwrap_ash()
          |> ash_update(:mark_verified_complete, session_context)
          |> unwrap_ash()

        task =
          Task
          |> ash_get_for_update(task.id)
          |> unwrap_ash()
          |> ash_update(:mark_verified_complete, session_context)
          |> unwrap_ash()

        %{
          artifact_graph_item: artifact_graph_item,
          artifact: artifact,
          evidence_graph_item: evidence_graph_item,
          evidence_item: evidence_item,
          verification_result: verification_result,
          verification_check: verification_check,
          review_finding: review_finding,
          task: task
        }
      end)
      |> case do
        {:ok, changes} ->
          trace!(operation, "artifact.create", "artifact", changes.artifact.id)
          trace!(operation, "evidence_item.create", "evidence_item", changes.evidence_item.id)

          trace!(
            operation,
            "verification_result.create",
            "verification_result",
            changes.verification_result.id
          )

          trace!(
            operation,
            "verification_check.satisfy",
            "verification_check",
            changes.verification_check.id
          )

          trace!(
            operation,
            "review_finding.complete",
            "review_finding",
            changes.review_finding.id
          )

          trace!(operation, "task.complete", "task", changes.task.id)

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

  defp transaction_result({:ok, changes}, key, operation, action, resource_type) do
    resource = Map.fetch!(changes, key)
    trace!(operation, action, resource_type, resource.id)
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

  defp ash_update(record, action, session_context) do
    record
    |> Ash.Changeset.for_update(action, %{}, actor: session_context)
    |> Ash.update(authorize?: true, return_notifications?: true)
    |> unwrap_ash_result()
  end

  defp ash_get_for_update(resource, id) do
    ash_get(resource, id)
  end

  defp ash_get(resource, id) do
    resource
    |> Ash.get(id,
      authorize?: false,
      not_found_error?: true
    )
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

  defp create_graph_item!(id, session_context, resource_type, resource_id, title) do
    ash_create(
      GraphItem,
      %{
        id: id,
        organization_id: session_context.organization_id,
        workspace_id: session_context.workspace_id,
        resource_type: resource_type,
        resource_id: resource_id,
        title: title
      },
      session_context
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

  defp trace!(operation, action, resource_type, resource_id) do
    Audit.record!(operation, action, resource_type, resource_id)
    Revisions.record!(operation, resource_type, resource_id, action, action)
  end
end
