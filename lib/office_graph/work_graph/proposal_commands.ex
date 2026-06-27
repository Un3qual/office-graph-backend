defmodule OfficeGraph.WorkGraph.ProposalCommands do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.WorkGraph.CommandSupport, as: Support

  alias OfficeGraph.WorkGraph.{
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck
  }

  @proposed_change_apply_action "proposed_change.apply"

  def create_signal(session_context, operation, attrs) do
    with :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @proposed_change_apply_action),
         :ok <- authorize_signal_create(session_context, operation) do
      signal_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Support.transaction(fn ->
        document = Support.create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          Support.create_graph_item!(
            graph_item_id,
            session_context,
            "signal",
            signal_id,
            attrs[:title]
          )

        signal =
          Support.ash_create(
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
          |> Support.unwrap_ash()

        Support.trace!(operation, "signal.create", "signal", signal.id)

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
    with :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @proposed_change_apply_action) do
      task_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Support.transaction(fn ->
        document = Support.create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          Support.create_graph_item!(
            graph_item_id,
            session_context,
            "task",
            task_id,
            attrs[:title]
          )

        task =
          Support.ash_create(
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
          |> Support.unwrap_ash()

        source_signal_graph_item_id = Support.persisted_graph_item_id!(Signal, signal.id)

        relationship =
          Support.create_relationship!(
            source_signal_graph_item_id,
            graph_item_id,
            "produced_task"
          )

        Support.trace!(operation, "task.create", "task", task.id)

        %{graph_item: graph_item, task: task, relationship: relationship}
      end)
      |> transaction_result(:task)
    end
  end

  def create_review_finding(session_context, operation, task, attrs) do
    with :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @proposed_change_apply_action) do
      finding_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Support.transaction(fn ->
        task =
          Task
          |> Support.ash_get_for_update(task.id)
          |> Support.unwrap_ash()

        Support.validate_scope!(session_context, task)
        Support.validate_open_task!(task)

        document = Support.create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          Support.create_graph_item!(
            graph_item_id,
            session_context,
            "review_finding",
            finding_id,
            attrs[:title]
          )

        review_finding =
          Support.ash_create(
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
          |> Support.unwrap_ash()

        relationship =
          Support.create_relationship!(
            task.graph_item_id,
            graph_item_id,
            "has_review_finding"
          )

        Support.trace!(operation, "review_finding.create", "review_finding", review_finding.id)

        %{graph_item: graph_item, review_finding: review_finding, relationship: relationship}
      end)
      |> transaction_result(:review_finding)
    end
  end

  def create_verification_check(session_context, operation, review_finding, attrs) do
    with :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @proposed_change_apply_action) do
      check_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Support.transaction(fn ->
        review_finding =
          ReviewFinding
          |> Support.ash_get_for_update(review_finding.id)
          |> Support.unwrap_ash()

        Support.validate_scope!(session_context, review_finding)
        Support.validate_open_review_finding!(review_finding)

        document = Support.create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          Support.create_graph_item!(
            graph_item_id,
            session_context,
            "verification_check",
            check_id,
            attrs[:title]
          )

        verification_check =
          Support.ash_create(
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
          |> Support.unwrap_ash()

        relationship =
          Support.create_relationship!(
            review_finding.graph_item_id,
            graph_item_id,
            "requires_verification"
          )

        Support.trace!(
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
      |> transaction_result(:verification_check)
    end
  end

  defp transaction_result({:ok, changes}, key) do
    {:ok, Map.take(changes, [:graph_item, key, :relationship])}
  end

  defp transaction_result({:error, changeset}, _key) do
    {:error, changeset}
  end

  defp authorize_signal_create(session_context, operation) do
    Authorization.authorize_operation(session_context, operation, :proposed_change_apply,
      organization_id: session_context.organization_id
    )
  end
end
