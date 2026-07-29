defmodule OfficeGraph.WorkGraph.ProposalCommands do
  @moduledoc false

  alias OfficeGraph.{Authorization, Operations}
  alias OfficeGraph.WorkGraph.CommandActionResult
  alias OfficeGraph.WorkGraph.CommandSupport, as: Support

  alias OfficeGraph.WorkGraph.{
    RelationshipCommands,
    RelationshipRequest,
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck
  }

  @proposed_change_apply_action "proposed_change.apply"

  @behaviour Ash.Resource.Actions.Implementation

  @impl true
  def run(input, [mode: :create_signal], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @proposed_change_apply_action),
         :ok <- authorize_signal_create(session_context, operation) do
      CommandActionResult.accepted(
        persist_signal!(session_context, operation, Map.delete(attrs, :operation_id))
      )
    end
    |> normalize_run_result()
  end

  def run(input, [mode: :create_task], %{actor: session_context})
      when is_map(session_context) do
    attrs = input.arguments

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @proposed_change_apply_action) do
      CommandActionResult.accepted(
        persist_task!(
          session_context,
          operation,
          %{id: attrs.signal_id},
          Map.drop(attrs, [:operation_id, :signal_id])
        )
      )
    end
    |> normalize_run_result()
  end

  def run(input, [mode: :create_review_finding], %{actor: session_context})
      when is_map(session_context) do
    persist_child_action(input, session_context, review_finding_options())
  end

  def run(input, [mode: :create_verification_check], %{actor: session_context})
      when is_map(session_context) do
    persist_child_action(input, session_context, verification_check_options())
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def create_signal(session_context, operation, attrs) do
    run_contract(
      Signal,
      :persist_signal_contract,
      attrs
      |> Map.new()
      |> Map.put(:operation_id, operation.id),
      session_context
    )
  end

  def create_task(session_context, operation, signal, attrs) do
    run_contract(
      Task,
      :persist_task_contract,
      attrs
      |> Map.new()
      |> Map.put(:operation_id, operation.id)
      |> Map.put(:signal_id, signal.id),
      session_context
    )
  end

  def create_review_finding(session_context, operation, task, attrs) do
    run_contract(
      ReviewFinding,
      :persist_review_finding_contract,
      attrs
      |> Map.new()
      |> Map.put(:operation_id, operation.id)
      |> Map.put(:task_id, task.id),
      session_context
    )
  end

  def create_verification_check(session_context, operation, review_finding, attrs) do
    run_contract(
      VerificationCheck,
      :persist_verification_check_contract,
      attrs
      |> Map.new()
      |> Map.put(:operation_id, operation.id)
      |> Map.put(:review_finding_id, review_finding.id),
      session_context
    )
  end

  defp persist_child_action(input, session_context, opts) do
    attrs = input.arguments
    parent_id = Map.fetch!(attrs, opts.parent_id_argument)

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id),
         :ok <- Support.validate_operation_context(session_context, operation),
         :ok <- Support.validate_operation_action(operation, @proposed_change_apply_action) do
      CommandActionResult.accepted(
        persist_child_node!(
          session_context,
          operation,
          %{id: parent_id},
          Map.drop(attrs, [:operation_id, opts.parent_id_argument]),
          opts
        )
      )
    end
    |> normalize_run_result()
  end

  defp review_finding_options do
    %{
      parent_id_argument: :task_id,
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
    }
  end

  defp verification_check_options do
    %{
      parent_id_argument: :review_finding_id,
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
    }
  end

  defp persist_signal!(session_context, operation, attrs) do
    signal_id = Ecto.UUID.generate()
    graph_item_id = Ecto.UUID.generate()
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
  end

  defp persist_task!(session_context, operation, signal, attrs) do
    task_id = Ecto.UUID.generate()
    graph_item_id = Ecto.UUID.generate()
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
      create_relationship!(
        session_context,
        operation,
        graph_item_id,
        source_signal_graph_item_id,
        "generated_from"
      )

    Support.trace!(operation, "task.create", "task", task.id)

    %{graph_item: graph_item, task: task, relationship: relationship}
  end

  defp persist_child_node!(session_context, operation, parent, attrs, opts) do
    child_id = Ecto.UUID.generate()
    graph_item_id = Ecto.UUID.generate()

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
      create_relationship!(
        session_context,
        operation,
        source_item_id,
        target_item_id,
        opts.relationship_key
      )

    Support.trace!(operation, opts.trace_action, opts.trace_resource, child.id)

    %{graph_item: graph_item, relationship: relationship}
    |> Map.put(opts.child_key, child)
  end

  defp authorize_signal_create(session_context, operation) do
    Authorization.authorize_operation(session_context, operation, :proposed_change_apply,
      organization_id: session_context.organization_id
    )
  end

  defp run_contract(resource, action, attrs, session_context) do
    resource
    |> Ash.ActionInput.for_action(action, attrs)
    |> Ash.run_action(actor: session_context, authorize?: false)
    |> Support.normalize_action_result()
    |> case do
      {:ok, %CommandActionResult{} = result} -> CommandActionResult.to_public_result(result)
      {:error, error} -> {:error, error}
    end
  end

  defp normalize_run_result({:ok, %CommandActionResult{}} = result), do: result
  defp normalize_run_result(%CommandActionResult{} = result), do: {:ok, result}

  defp normalize_run_result({:error, error}),
    do: CommandActionResult.rejected(error)

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
