defmodule OfficeGraph.WorkGraph.SystemCommands do
  @moduledoc false

  alias OfficeGraph.{Content, Operations, Repo}
  alias OfficeGraph.WorkGraph.CommandSupport, as: Support

  alias OfficeGraph.WorkGraph.{
    GraphItem,
    GraphRelationship,
    RelationshipCommands,
    RelationshipDefinitions,
    RelationshipRequest,
    Signal
  }

  require Ash.Query

  def ensure_integration_signal(operation, reference, attrs)
      when is_map(operation) and is_map(reference) and is_map(attrs),
      do: sync_integration_signal(operation, reference, attrs, true)

  def ensure_integration_signal(_operation, _reference, _attrs), do: {:error, :forbidden}

  def sync_integration_signal(operation, reference, attrs, actionable?)
      when is_map(operation) and is_map(reference) and is_map(attrs) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         true <- is_binary(operation.workspace_id),
         true <- is_binary(Map.get(reference, :id)),
         true <- Map.get(reference, :organization_id) == operation.organization_id,
         true <- Map.get(reference, :workspace_id) == operation.workspace_id,
         true <- is_boolean(actionable?),
         {:ok, {title, body}} <- signal_content(attrs, actionable?) do
      transact(fn -> sync_signal!(operation, reference, title, body, actionable?) end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, error} when is_struct(error) -> {:error, :integration_storage_unavailable}
        {:error, error} -> {:error, error}
      end
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def sync_integration_signal(_operation, _reference, _attrs, _actionable?),
    do: {:error, :forbidden}

  defp sync_signal!(operation, reference, title, body, true) do
    reference_item =
      operation
      |> ensure_reference_item!(reference, title)
      |> then(&Support.ash_get_for_update(GraphItem, &1.id))
      |> Support.unwrap_ash()

    case signal_for_reference(operation.principal_id, reference_item.id) do
      {:ok, nil} -> create_signal!(operation, reference_item, title, body)
      {:ok, signal} -> sync_existing_signal!(operation, signal, title, body)
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp sync_signal!(operation, reference, _title, _body, false) do
    case reference_item_for_update!(operation, reference.id) do
      nil ->
        %{signal: nil, created?: false, state_changed?: false}

      reference_item ->
        case signal_for_reference(operation.principal_id, reference_item.id) do
          {:ok, nil} -> %{signal: nil, created?: false, state_changed?: false}
          {:ok, signal} -> transition_signal!(operation, signal, "closed")
          {:error, error} -> Repo.rollback(error)
        end
    end
  end

  defp ensure_reference_item!(operation, reference, title) do
    GraphItem
    |> Ash.Query.filter(resource_type == "external_reference" and resource_id == ^reference.id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        _created_or_conflicted =
          Support.ash_create_internal(
            GraphItem,
            reference_item_attrs(operation, reference, title),
            upsert?: true,
            upsert_identity: :unique_resource,
            upsert_fields: []
          )
          |> Support.unwrap_ash()

        fetch_reference_item!(operation, reference.id)

      {:ok, item} ->
        if item.organization_id == operation.organization_id and
             item.workspace_id == operation.workspace_id,
           do: item,
           else: Repo.rollback(:forbidden)

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp reference_item_attrs(operation, reference, title) do
    [
      id: Ecto.UUID.generate(),
      organization_id: operation.organization_id,
      workspace_id: operation.workspace_id,
      resource_type: "external_reference",
      resource_id: reference.id,
      title: title
    ]
    |> Map.new()
  end

  defp fetch_reference_item!(operation, reference_id) do
    GraphItem
    |> Ash.Query.filter(resource_type == "external_reference" and resource_id == ^reference_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %GraphItem{} = item}
      when item.organization_id == operation.organization_id and
             item.workspace_id == operation.workspace_id ->
        item

      {:ok, nil} ->
        Repo.rollback(:provider_identity_conflict)

      {:ok, _cross_scope} ->
        Repo.rollback(:forbidden)

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp reference_item_for_update!(operation, reference_id) do
    GraphItem
    |> Ash.Query.filter(resource_type == "external_reference" and resource_id == ^reference_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        nil

      {:ok, %GraphItem{} = item}
      when item.organization_id == operation.organization_id and
             item.workspace_id == operation.workspace_id ->
        GraphItem
        |> Support.ash_get_for_update(item.id)
        |> Support.unwrap_ash()

      {:ok, _cross_scope} ->
        Repo.rollback(:forbidden)

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp signal_for_reference(asserting_principal_id, reference_item_id) do
    with {:ok, definition} <- RelationshipDefinitions.fetch_by_key("references_external"),
         {:ok, relationship} <-
           active_reference_relationship(
             definition.id,
             asserting_principal_id,
             reference_item_id
           ) do
      case relationship do
        nil -> {:ok, nil}
        relationship -> signal_by_graph_item(relationship.source_item_id)
      end
    end
  end

  defp active_reference_relationship(
         definition_id,
         asserting_principal_id,
         reference_item_id
       ) do
    GraphRelationship
    |> Ash.Query.filter(
      definition_id == ^definition_id and target_item_id == ^reference_item_id and
        asserting_principal_id == ^asserting_principal_id and lifecycle == "active" and
        source_item.resource_type == "signal"
    )
    |> Ash.read_one(authorize?: false)
  end

  defp signal_by_graph_item(graph_item_id) do
    Signal
    |> Ash.Query.filter(graph_item_id == ^graph_item_id)
    |> Ash.read_one(authorize?: false)
  end

  defp create_signal!(operation, reference_item, title, body) do
    document =
      operation
      |> Content.create_system_plain_document(body)
      |> Support.unwrap_content()

    signal_id = Ecto.UUID.generate()
    graph_item_id = Ecto.UUID.generate()
    context = %{organization_id: operation.organization_id, workspace_id: operation.workspace_id}

    _signal_item =
      Support.create_graph_item!(graph_item_id, context, "signal", signal_id, title)

    signal =
      Support.ash_create_internal(Signal, %{
        id: signal_id,
        organization_id: operation.organization_id,
        workspace_id: operation.workspace_id,
        graph_item_id: graph_item_id,
        body_document_id: document.id,
        title: title
      })
      |> Support.unwrap_ash()

    request =
      RelationshipRequest.new!(%{
        definition_key: "references_external",
        source_item_id: graph_item_id,
        target_item_id: reference_item.id,
        workspace_id: operation.workspace_id
      })

    relationship =
      operation
      |> RelationshipCommands.create_system(request)
      |> Support.unwrap_ash()

    Support.trace!(operation, "signal.create", "signal", signal.id)

    %{signal: signal, relationship: relationship, created?: true}
  end

  defp sync_existing_signal!(operation, signal, title, body) do
    signal = Signal |> Support.ash_get_for_update(signal.id) |> Support.unwrap_ash()

    graph_item =
      GraphItem
      |> Support.ash_get_for_update(signal.graph_item_id)
      |> Support.unwrap_ash()

    current_body =
      operation
      |> Content.system_plain_text_for_document(signal.body_document_id)
      |> Support.unwrap_content()

    state_changed? = signal.state != "open"
    signal_title_changed? = signal.title != title
    graph_title_changed? = graph_item.title != title
    body_changed? = current_body != body
    content_changed? = signal_title_changed? or graph_title_changed? or body_changed?

    attrs =
      %{}
      |> maybe_put(:state, "open", state_changed?)
      |> maybe_put(:title, title, signal_title_changed?)

    attrs =
      if body_changed? do
        document =
          operation
          |> Content.create_system_plain_document(body)
          |> Support.unwrap_content()

        Map.put(attrs, :body_document_id, document.id)
      else
        attrs
      end

    updated_signal =
      if attrs == %{} do
        signal
      else
        signal
        |> Support.ash_update_internal(:sync_integration, attrs)
        |> Support.unwrap_ash()
      end

    if graph_title_changed? do
      graph_item
      |> Support.ash_update_internal(:set_title, %{title: title})
      |> Support.unwrap_ash()
    end

    if content_changed?, do: Support.trace!(operation, "signal.refresh", "signal", signal.id)
    if state_changed?, do: Support.trace!(operation, "signal.open", "signal", signal.id)

    %{
      signal: updated_signal,
      created?: false,
      state_changed?: state_changed?,
      content_changed?: content_changed?
    }
  end

  defp transition_signal!(_operation, %{state: state} = signal, state),
    do: %{signal: signal, created?: false, state_changed?: false}

  defp transition_signal!(operation, signal, state) do
    updated =
      signal
      |> Support.ash_update_internal(:set_state, %{state: state})
      |> Support.unwrap_ash()

    Support.trace!(operation, "signal.#{state}", "signal", updated.id)
    %{signal: updated, created?: false, state_changed?: true}
  end

  defp required_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, {:invalid_integration_signal, key}}
    end
  end

  defp signal_content(attrs, true) do
    with {:ok, title} <- required_string(attrs, :title),
         {:ok, body} <- required_string(attrs, :body),
         do: {:ok, {title, body}}
  end

  defp signal_content(_attrs, false), do: {:ok, {nil, nil}}

  defp maybe_put(attrs, _key, _value, false), do: attrs
  defp maybe_put(attrs, key, value, true), do: Map.put(attrs, key, value)

  defp transact(fun), do: Repo.transaction(fun)
end
