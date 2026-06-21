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
    GraphItem,
    GraphRelationship
  }

  alias OfficeGraph.WorkGraph.ReviewFinding, as: ReviewFindingSchema
  alias OfficeGraph.WorkGraph.Task, as: TaskSchema
  alias OfficeGraph.WorkGraph.VerificationCheck, as: VerificationCheckSchema

  alias OfficeGraph.WorkGraph.Resources.{
    Artifact,
    EvidenceItem,
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck,
    VerificationResult
  }

  def get_verification_check!(id), do: Repo.get!(VerificationCheckSchema, id)

  def create_signal(session_context, operation, attrs) do
    with :ok <-
           Authorization.authorize(session_context, :manual_intake_submit,
             organization_id: session_context.organization_id
           ),
         {:ok, document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      signal_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Repo.transaction(fn ->
        graph_item =
          insert_graph_item!(
            graph_item_id,
            session_context,
            "signal",
            signal_id,
            attrs[:title]
          )

        signal =
          ash_create!(
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

        %{graph_item: graph_item, signal: signal}
      end)
      |> case do
        {:ok, %{graph_item: graph_item, signal: signal}} ->
          trace!(operation, "signal.create", "signal", signal.id)
          {:ok, %{graph_item: graph_item, signal: signal, document: document}}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def create_task(session_context, operation, signal, attrs) do
    with {:ok, document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      task_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Repo.transaction(fn ->
        graph_item =
          insert_graph_item!(graph_item_id, session_context, "task", task_id, attrs[:title])

        task =
          ash_create!(
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

        relationship =
          insert_relationship!(signal.graph_item_id, graph_item_id, "produced_task")

        %{graph_item: graph_item, task: task, relationship: relationship}
      end)
      |> transaction_result(:task, operation, "task.create", "task")
    end
  end

  def create_review_finding(session_context, operation, task, attrs) do
    with {:ok, document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      finding_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Repo.transaction(fn ->
        graph_item =
          insert_graph_item!(
            graph_item_id,
            session_context,
            "review_finding",
            finding_id,
            attrs[:title]
          )

        review_finding =
          ash_create!(
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

        relationship =
          insert_relationship!(task.graph_item_id, graph_item_id, "has_review_finding")

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
    with {:ok, document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      check_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Repo.transaction(fn ->
        graph_item =
          insert_graph_item!(
            graph_item_id,
            session_context,
            "verification_check",
            check_id,
            attrs[:title]
          )

        verification_check =
          ash_create!(
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

        relationship =
          insert_relationship!(
            review_finding.graph_item_id,
            graph_item_id,
            "requires_verification"
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
    with {:ok, evidence_document} <-
           Content.create_plain_document(session_context, operation, attrs[:body] || "") do
      review_finding = Repo.get!(ReviewFindingSchema, verification_check.review_finding_id)
      task = Repo.get!(TaskSchema, review_finding.task_id)

      artifact_id = Ecto.UUID.generate()
      artifact_graph_item_id = Ecto.UUID.generate()
      evidence_id = Ecto.UUID.generate()
      evidence_graph_item_id = Ecto.UUID.generate()
      verification_result_id = Ecto.UUID.generate()

      Repo.transaction(fn ->
        artifact_graph_item =
          insert_graph_item!(
            artifact_graph_item_id,
            session_context,
            "artifact",
            artifact_id,
            attrs[:title]
          )

        artifact =
          ash_create!(
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

        evidence_graph_item =
          insert_graph_item!(
            evidence_graph_item_id,
            session_context,
            "evidence_item",
            evidence_id,
            attrs[:title]
          )

        evidence_item =
          ash_create!(
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

        verification_result =
          ash_create!(
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

        verification_check =
          VerificationCheck
          |> Ash.get!(verification_check.id, actor: session_context, authorize?: true)
          |> ash_update!(:mark_satisfied, session_context)

        review_finding =
          ReviewFinding
          |> Ash.get!(review_finding.id, actor: session_context, authorize?: true)
          |> ash_update!(:mark_verified_complete, session_context)

        task =
          Task
          |> Ash.get!(task.id, actor: session_context, authorize?: true)
          |> ash_update!(:mark_verified_complete, session_context)

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

        {:error, changeset} ->
          {:error, changeset}
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

  defp ash_create!(resource, attrs, session_context) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, actor: session_context)
    |> Ash.create!(authorize?: true)
  end

  defp ash_update!(record, action, session_context) do
    record
    |> Ash.Changeset.for_update(action, %{}, actor: session_context)
    |> Ash.update!(authorize?: true)
  end

  defp insert_graph_item!(id, session_context, resource_type, resource_id, title) do
    %GraphItem{id: id}
    |> GraphItem.changeset(%{
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id,
      resource_type: resource_type,
      resource_id: resource_id,
      title: title
    })
    |> Repo.insert!()
  end

  defp insert_relationship!(source_item_id, target_item_id, relationship_type) do
    %GraphRelationship{}
    |> GraphRelationship.changeset(%{
      source_item_id: source_item_id,
      target_item_id: target_item_id,
      relationship_type: relationship_type
    })
    |> Repo.insert!()
  end

  defp trace!(operation, action, resource_type, resource_id) do
    Audit.record!(operation, action, resource_type, resource_id)
    Revisions.record!(operation, resource_type, resource_id, action, action)
  end
end
