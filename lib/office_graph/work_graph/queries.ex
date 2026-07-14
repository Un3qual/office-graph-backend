defmodule OfficeGraph.WorkGraph.Queries do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.WorkGraph.{GraphItem, GraphRelationship, Signal, VerificationCheck}

  require Ash.Query

  def graphql_node_type(%Signal{}), do: :signal

  def graphql_node_type(%{definition_key: _key, source: _source, target: _target}),
    do: :graph_relationship_view

  def graphql_node_type(_value), do: nil

  def graphql_node(session_context, :signal, id) do
    Ash.get(Signal, id, actor: session_context, not_found_error?: false)
  end

  def graphql_node(session_context, :graph_relationship_view, id) do
    get_relationship(session_context, id)
  end

  def graphql_node(_session_context, _type, _id), do: {:ok, nil}

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

  def list_relationships(session_context, item_id, opts \\ []) do
    with {:ok, normalized_opts} <- normalize_relationship_opts(opts),
         :ok <-
           Authorization.authorize_projection(session_context, :skeleton_read,
             organization_id: session_context.organization_id
           ),
         {:ok, _item} <- authorized_item(session_context, item_id),
         {:ok, relationships} <-
           read_adjacency(session_context, item_id, normalized_opts),
         {:ok, endpoints} <- batch_authorized_endpoints(session_context, relationships) do
      {:ok, Enum.map(relationships, &relationship_view(&1, endpoints))}
    end
  end

  def get_relationship(session_context, relationship_id) do
    with :ok <-
           Authorization.authorize_projection(session_context, :skeleton_read,
             organization_id: session_context.organization_id
           ) do
      case read_relationship(session_context, relationship_id) do
        {:ok, nil} ->
          {:ok, nil}

        {:ok, relationship} ->
          with {:ok, endpoints} <- batch_authorized_endpoints(session_context, [relationship]) do
            if visible_endpoint?(relationship, endpoints) do
              {:ok, relationship_view(relationship, endpoints)}
            else
              {:ok, nil}
            end
          end

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp authorized_item(session_context, item_id) do
    GraphItem
    |> Ash.Query.filter(
      id == ^item_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %GraphItem{} = item} -> {:ok, item}
      _result -> {:error, :forbidden}
    end
  end

  defp read_adjacency(session_context, item_id, opts) do
    GraphRelationship
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and
        lifecycle == ^opts.lifecycle
    )
    |> filter_relationship_direction(item_id, opts.direction)
    |> filter_relationship_definitions(opts.definition_keys)
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(opts.limit)
    |> Ash.Query.load(:definition)
    |> Ash.read(authorize?: false)
  end

  defp read_relationship(session_context, relationship_id) do
    GraphRelationship
    |> Ash.Query.filter(
      id == ^relationship_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.Query.load(:definition)
    |> Ash.read_one(authorize?: false)
  end

  defp filter_relationship_direction(query, item_id, :incoming) do
    Ash.Query.filter(query, target_item_id == ^item_id)
  end

  defp filter_relationship_direction(query, item_id, :outgoing) do
    Ash.Query.filter(query, source_item_id == ^item_id)
  end

  defp filter_relationship_direction(query, item_id, :both) do
    Ash.Query.filter(query, source_item_id == ^item_id or target_item_id == ^item_id)
  end

  defp filter_relationship_definitions(query, nil), do: query

  defp filter_relationship_definitions(query, definition_keys) do
    Ash.Query.filter(query, definition.key in ^definition_keys)
  end

  defp batch_authorized_endpoints(session_context, relationships) do
    endpoint_ids =
      relationships
      |> Enum.flat_map(&[&1.source_item_id, &1.target_item_id])
      |> Enum.uniq()

    GraphItem
    |> Ash.Query.filter(
      id in ^endpoint_ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, items} -> {:ok, Map.new(items, &{&1.id, &1})}
      {:error, _error} -> {:error, :forbidden}
    end
  end

  defp relationship_view(relationship, endpoints) do
    %{
      id: relationship.id,
      definition_key: relationship.definition.key,
      family: relationship.definition.family,
      direction: relationship.definition.direction,
      lifecycle: relationship.lifecycle,
      governing_workspace_id: relationship.workspace_id,
      valid_from: relationship.valid_from,
      valid_until: relationship.valid_until,
      operation_id: relationship.operation_id,
      run_id: relationship.run_id,
      integration_event_id: relationship.integration_event_id,
      supersedes_relationship_id: relationship.supersedes_relationship_id,
      tombstone_id: relationship.tombstone_id,
      source: endpoint_view(relationship.source_item_id, endpoints),
      target: endpoint_view(relationship.target_item_id, endpoints)
    }
  end

  defp visible_endpoint?(relationship, endpoints) do
    Map.has_key?(endpoints, relationship.source_item_id) or
      Map.has_key?(endpoints, relationship.target_item_id)
  end

  defp endpoint_view(id, endpoints) do
    case Map.fetch(endpoints, id) do
      {:ok, item} ->
        %{
          visibility: :visible,
          id: item.id,
          workspace_id: item.workspace_id,
          resource_type: item.resource_type,
          title: item.title
        }

      :error ->
        %{visibility: :redacted}
    end
  end

  defp normalize_relationship_opts(opts) when is_list(opts) do
    with {:ok, direction} <- normalize_direction(Keyword.get(opts, :direction, :both)),
         {:ok, definition_keys} <-
           normalize_definition_keys(Keyword.get(opts, :definition_keys)),
         {:ok, lifecycle} <- normalize_lifecycle(Keyword.get(opts, :lifecycle, "active")),
         {:ok, limit} <- normalize_limit(Keyword.get(opts, :limit, 25)) do
      {:ok,
       %{
         direction: direction,
         definition_keys: definition_keys,
         lifecycle: lifecycle,
         limit: limit
       }}
    end
  end

  defp normalize_relationship_opts(_opts),
    do: {:error, {:invalid_relationship_option, :options}}

  defp normalize_direction(direction) when direction in [:incoming, :outgoing, :both],
    do: {:ok, direction}

  defp normalize_direction(_direction),
    do: {:error, {:invalid_relationship_option, :direction}}

  defp normalize_definition_keys(nil), do: {:ok, nil}

  defp normalize_definition_keys(definition_keys) when is_list(definition_keys) do
    if Enum.all?(definition_keys, &(is_binary(&1) and &1 != "")) do
      {:ok, Enum.uniq(definition_keys)}
    else
      {:error, {:invalid_relationship_option, :definition_keys}}
    end
  end

  defp normalize_definition_keys(_definition_keys),
    do: {:error, {:invalid_relationship_option, :definition_keys}}

  defp normalize_lifecycle(lifecycle) when lifecycle in ["active", "archived"],
    do: {:ok, lifecycle}

  defp normalize_lifecycle(_lifecycle),
    do: {:error, {:invalid_relationship_option, :lifecycle}}

  defp normalize_limit(limit) when is_integer(limit),
    do: {:ok, limit |> max(1) |> min(100)}

  defp normalize_limit(_limit),
    do: {:error, {:invalid_relationship_option, :limit}}
end
