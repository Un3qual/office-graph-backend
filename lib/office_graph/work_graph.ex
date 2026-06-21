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
  alias Ecto.Multi
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

  def get_verification_check!(id), do: Repo.get!(VerificationCheck, id)

  def create_signal(session_context, operation, attrs) do
    with :ok <-
           Authorization.authorize(session_context, :manual_intake_submit,
             organization_id: session_context.organization_id
           ),
         {:ok, document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      signal_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Multi.new()
      |> Multi.insert(
        :graph_item,
        GraphItem.changeset(%GraphItem{id: graph_item_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          resource_type: "signal",
          resource_id: signal_id,
          title: attrs[:title]
        })
      )
      |> Multi.insert(
        :signal,
        Signal.changeset(%Signal{id: signal_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          graph_item_id: graph_item_id,
          body_document_id: document.id,
          title: attrs[:title],
          state: "open"
        })
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{graph_item: graph_item, signal: signal}} ->
          trace!(operation, "signal.create", "signal", signal.id)
          {:ok, %{graph_item: graph_item, signal: signal, document: document}}

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  def create_task(session_context, operation, signal, attrs) do
    with {:ok, document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      task_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Multi.new()
      |> Multi.insert(
        :graph_item,
        GraphItem.changeset(%GraphItem{id: graph_item_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          resource_type: "task",
          resource_id: task_id,
          title: attrs[:title]
        })
      )
      |> Multi.insert(
        :task,
        Task.changeset(%Task{id: task_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          graph_item_id: graph_item_id,
          source_signal_id: signal.id,
          body_document_id: document.id,
          title: attrs[:title],
          lifecycle_state: "open"
        })
      )
      |> Multi.insert(
        :relationship,
        GraphRelationship.changeset(%GraphRelationship{}, %{
          source_item_id: signal.graph_item_id,
          target_item_id: graph_item_id,
          relationship_type: "produced_task"
        })
      )
      |> transaction_result(operation, :task, "task.create", "task")
    end
  end

  def create_review_finding(session_context, operation, task, attrs) do
    with {:ok, document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      finding_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Multi.new()
      |> Multi.insert(
        :graph_item,
        GraphItem.changeset(%GraphItem{id: graph_item_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          resource_type: "review_finding",
          resource_id: finding_id,
          title: attrs[:title]
        })
      )
      |> Multi.insert(
        :review_finding,
        ReviewFinding.changeset(%ReviewFinding{id: finding_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          graph_item_id: graph_item_id,
          task_id: task.id,
          body_document_id: document.id,
          title: attrs[:title],
          lifecycle_state: "open"
        })
      )
      |> Multi.insert(
        :relationship,
        GraphRelationship.changeset(%GraphRelationship{}, %{
          source_item_id: task.graph_item_id,
          target_item_id: graph_item_id,
          relationship_type: "has_review_finding"
        })
      )
      |> transaction_result(operation, :review_finding, "review_finding.create", "review_finding")
    end
  end

  def create_verification_check(session_context, operation, review_finding, attrs) do
    with {:ok, document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      check_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Multi.new()
      |> Multi.insert(
        :graph_item,
        GraphItem.changeset(%GraphItem{id: graph_item_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          resource_type: "verification_check",
          resource_id: check_id,
          title: attrs[:title]
        })
      )
      |> Multi.insert(
        :verification_check,
        VerificationCheck.changeset(%VerificationCheck{id: check_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          graph_item_id: graph_item_id,
          review_finding_id: review_finding.id,
          description_document_id: document.id,
          title: attrs[:title],
          lifecycle_state: "required"
        })
      )
      |> Multi.insert(
        :relationship,
        GraphRelationship.changeset(%GraphRelationship{}, %{
          source_item_id: review_finding.graph_item_id,
          target_item_id: graph_item_id,
          relationship_type: "requires_verification"
        })
      )
      |> transaction_result(
        operation,
        :verification_check,
        "verification_check.create",
        "verification_check"
      )
    end
  end

  def complete_verification(session_context, operation, verification_check, attrs) do
    with {:ok, evidence_document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      review_finding = Repo.get!(ReviewFinding, verification_check.review_finding_id)
      task = Repo.get!(Task, review_finding.task_id)

      artifact_id = Ecto.UUID.generate()
      artifact_graph_item_id = Ecto.UUID.generate()
      evidence_id = Ecto.UUID.generate()
      evidence_graph_item_id = Ecto.UUID.generate()

      Multi.new()
      |> Multi.insert(
        :artifact_graph_item,
        GraphItem.changeset(%GraphItem{id: artifact_graph_item_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          resource_type: "artifact",
          resource_id: artifact_id,
          title: attrs[:title]
        })
      )
      |> Multi.insert(
        :artifact,
        Artifact.changeset(%Artifact{id: artifact_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          graph_item_id: artifact_graph_item_id,
          title: attrs[:title],
          uri: attrs[:artifact_uri]
        })
      )
      |> Multi.insert(
        :evidence_graph_item,
        GraphItem.changeset(%GraphItem{id: evidence_graph_item_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          resource_type: "evidence_item",
          resource_id: evidence_id,
          title: attrs[:title]
        })
      )
      |> Multi.insert(
        :evidence_item,
        EvidenceItem.changeset(%EvidenceItem{id: evidence_id}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          graph_item_id: evidence_graph_item_id,
          verification_check_id: verification_check.id,
          artifact_id: artifact_id,
          body_document_id: evidence_document.id,
          title: attrs[:title],
          state: "accepted"
        })
      )
      |> Multi.insert(
        :verification_result,
        VerificationResult.changeset(%VerificationResult{}, %{
          organization_id: session_context.organization_id,
          workspace_id: session_context.workspace_id,
          verification_check_id: verification_check.id,
          evidence_item_id: evidence_id,
          operation_id: operation.id,
          result: "passed"
        })
      )
      |> Multi.update(
        :verification_check,
        VerificationCheck.changeset(verification_check, %{lifecycle_state: "satisfied"})
      )
      |> Multi.update(
        :review_finding,
        ReviewFinding.changeset(review_finding, %{lifecycle_state: "verified_complete"})
      )
      |> Multi.update(
        :task,
        Task.changeset(task, %{lifecycle_state: "verified_complete"})
      )
      |> Repo.transaction()
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

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  defp transaction_result(multi, operation, key, action, resource_type) do
    case Repo.transaction(multi) do
      {:ok, changes} ->
        resource = Map.fetch!(changes, key)
        trace!(operation, action, resource_type, resource.id)
        {:ok, Map.take(changes, [:graph_item, key, :relationship])}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp trace!(operation, action, resource_type, resource_id) do
    Audit.record!(operation, action, resource_type, resource_id)
    Revisions.record!(operation, resource_type, resource_id, action, action)
  end
end
