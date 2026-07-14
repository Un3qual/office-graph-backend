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
      when is_map(operation) and is_map(reference) and is_map(attrs) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         true <- is_binary(operation.workspace_id),
         true <- is_binary(Map.get(reference, :id)),
         true <- reference.organization_id == operation.organization_id,
         {:ok, title} <- required_string(attrs, :title),
         {:ok, body} <- required_string(attrs, :body) do
      transact(fn ->
        reference_item =
          operation
          |> ensure_reference_item!(reference, title)
          |> then(&Support.ash_get_for_update(GraphItem, &1.id))
          |> Support.unwrap_ash()

        case signal_for_reference(reference_item.id) do
          {:ok, nil} -> create_signal!(operation, reference_item, title, body)
          {:ok, signal} -> %{signal: signal, created?: false}
          {:error, error} -> Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, error} -> {:error, error}
      end
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def ensure_integration_signal(_operation, _reference, _attrs), do: {:error, :forbidden}

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

  defp signal_for_reference(reference_item_id) do
    with {:ok, definition} <- RelationshipDefinitions.fetch_by_key("references_external"),
         {:ok, relationship} <- active_reference_relationship(definition.id, reference_item_id) do
      case relationship do
        nil -> {:ok, nil}
        relationship -> signal_by_graph_item(relationship.source_item_id)
      end
    end
  end

  defp active_reference_relationship(definition_id, reference_item_id) do
    GraphRelationship
    |> Ash.Query.filter(
      definition_id == ^definition_id and target_item_id == ^reference_item_id and
        lifecycle == "active"
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

  defp required_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, {:invalid_integration_signal, key}}
    end
  end

  defp transact(fun), do: Repo.transaction(fun)
end
