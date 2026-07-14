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
            session_context,
            operation,
            graph_item_id,
            source_signal_graph_item_id,
            "generated_from"
          )

        Support.trace!(operation, "task.create", "task", task.id)

        %{graph_item: graph_item, task: task, relationship: relationship}
      end)
      |> transaction_result(:task)
    end
  end

  def create_review_finding(session_context, operation, task, attrs) do
    create_child_node(session_context, operation, task, attrs, %{
      parent_resource: Task,
      child_resource: ReviewFinding,
      child_key: :review_finding,
      resource_type: "review_finding",
      relationship_key: "review_finding_for",
      relationship_direction: :child_to_parent,
      trace_action: "review_finding.create",
      trace_resource: "review_finding",
      child_attrs: fn task, document ->
        %{task_id: task.id, body_document_id: document.id}
      end
    })
  end

  def create_verification_check(session_context, operation, review_finding, attrs) do
    create_child_node(session_context, operation, review_finding, attrs, %{
      parent_resource: ReviewFinding,
      child_resource: VerificationCheck,
      child_key: :verification_check,
      resource_type: "verification_check",
      relationship_key: "requires_check",
      relationship_direction: :parent_to_child,
      trace_action: "verification_check.create",
      trace_resource: "verification_check",
      child_attrs: fn review_finding, document ->
        %{review_finding_id: review_finding.id, description_document_id: document.id}
      end
    })
  end

  defp create_child_node(session_context, operation, parent, attrs, opts) do
    with :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @proposed_change_apply_action) do
      child_id = Ecto.UUID.generate()
      graph_item_id = Ecto.UUID.generate()

      Support.transaction(fn ->
        parent =
          opts.parent_resource
          |> Support.ash_get_for_update(parent.id)
          |> Support.unwrap_ash()

        document = Support.create_document!(session_context, operation, attrs[:body] || "")

        graph_item =
          Support.create_graph_item!(
            graph_item_id,
            session_context,
            opts.resource_type,
            child_id,
            attrs[:title]
          )

        child_attrs =
          Map.merge(
            %{
              id: child_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              graph_item_id: graph_item_id,
              title: attrs[:title]
            },
            opts.child_attrs.(parent, document)
          )

        child =
          Support.ash_create(
            opts.child_resource,
            child_attrs,
            session_context
          )
          |> Support.unwrap_ash()

        {source_item_id, target_item_id} =
          case opts.relationship_direction do
            :child_to_parent -> {graph_item_id, parent.graph_item_id}
            :parent_to_child -> {parent.graph_item_id, graph_item_id}
          end

        relationship =
          Support.create_relationship!(
            session_context,
            operation,
            source_item_id,
            target_item_id,
            opts.relationship_key
          )

        Support.trace!(operation, opts.trace_action, opts.trace_resource, child.id)

        %{graph_item: graph_item, relationship: relationship}
        |> Map.put(opts.child_key, child)
      end)
      |> transaction_result(opts.child_key)
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
