defmodule OfficeGraphWeb.JsonApi.Relationships.Controller do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.WorkGraph
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.RequestSession

  def index(conn, %{"item_id" => item_id} = params) do
    with {:ok, session_context} <- request_session(conn),
         {:ok, opts} <- relationship_opts(params),
         {:ok, relationships} <-
           WorkGraph.list_relationships(session_context, item_id, opts) do
      json(conn, %{data: Enum.map(relationships, &serialize_relationship/1)})
    else
      {:error, {:invalid_relationship_option, field}} ->
        Errors.render(conn, {:error, {:invalid_field, field}})

      error ->
        Errors.render(conn, error)
    end
  end

  defp request_session(conn) do
    conn
    |> Ash.PlugHelpers.get_actor()
    |> RequestSession.resolve()
  end

  defp relationship_opts(params) do
    with {:ok, direction} <- parse_direction(Map.get(params, "direction")),
         {:ok, definition_keys} <- parse_definition_keys(Map.get(params, "definition_keys")),
         {:ok, lifecycle} <- parse_lifecycle(Map.get(params, "lifecycle")),
         {:ok, limit} <- parse_limit(Map.get(params, "limit")) do
      {:ok,
       [
         direction: direction,
         definition_keys: definition_keys,
         lifecycle: lifecycle,
         limit: limit
       ]}
    end
  end

  defp parse_direction(nil), do: {:ok, :both}
  defp parse_direction("incoming"), do: {:ok, :incoming}
  defp parse_direction("outgoing"), do: {:ok, :outgoing}
  defp parse_direction("both"), do: {:ok, :both}
  defp parse_direction(_direction), do: {:error, {:invalid_field, :direction}}

  defp parse_definition_keys(nil), do: {:ok, nil}

  defp parse_definition_keys(keys) when is_binary(keys) do
    keys = keys |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if keys == [] or Enum.any?(keys, &(&1 == "")) do
      {:error, {:invalid_field, :definition_keys}}
    else
      {:ok, keys}
    end
  end

  defp parse_definition_keys(keys) when is_list(keys), do: {:ok, keys}

  defp parse_definition_keys(_keys),
    do: {:error, {:invalid_field, :definition_keys}}

  defp parse_lifecycle(nil), do: {:ok, "active"}
  defp parse_lifecycle(lifecycle) when lifecycle in ["active", "archived"], do: {:ok, lifecycle}
  defp parse_lifecycle(_lifecycle), do: {:error, {:invalid_field, :lifecycle}}

  defp parse_limit(nil), do: {:ok, 25}

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {limit, ""} -> {:ok, limit}
      _result -> {:error, {:invalid_field, :limit}}
    end
  end

  defp parse_limit(limit) when is_integer(limit), do: {:ok, limit}
  defp parse_limit(_limit), do: {:error, {:invalid_field, :limit}}

  defp serialize_relationship(relationship) do
    %{
      type: "graph_relationship",
      id: relationship.id,
      attributes: %{
        definition_key: relationship.definition_key,
        family: relationship.family,
        direction: relationship.direction,
        lifecycle: relationship.lifecycle,
        governing_workspace_id: relationship.governing_workspace_id,
        valid_from: relationship.valid_from,
        valid_until: relationship.valid_until,
        operation_id: relationship.operation_id,
        run_id: relationship.run_id,
        integration_event_id: relationship.integration_event_id,
        supersedes_relationship_id: relationship.supersedes_relationship_id,
        tombstone_id: relationship.tombstone_id,
        source: serialize_endpoint(relationship.source),
        target: serialize_endpoint(relationship.target)
      }
    }
  end

  defp serialize_endpoint(%{visibility: :visible} = endpoint) do
    %{
      visibility: "visible",
      id: endpoint.id,
      workspace_id: endpoint.workspace_id,
      resource_type: endpoint.resource_type,
      title: endpoint.title
    }
  end

  defp serialize_endpoint(%{visibility: :redacted}), do: %{visibility: "redacted"}
end
