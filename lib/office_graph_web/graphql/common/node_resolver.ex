defmodule OfficeGraphWeb.GraphQL.Common.NodeResolver do
  @moduledoc false

  alias OfficeGraph.Projections
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.RequestSession

  @domains [
    OfficeGraph.WorkGraph.Domain,
    OfficeGraph.WorkPackets.Domain,
    OfficeGraph.Runs.Domain,
    OfficeGraph.AgentRuntime.Domain,
    OfficeGraph.NodeConversations.Domain
  ]

  @custom_node_types [:graph_relationship_view, :operator_workflow_item]

  def call(%{arguments: %{id: id}} = resolution, _config) do
    case decode_node_id(id, resolution.schema) do
      {:ok, %{type: type, id: source_id}} when type in @custom_node_types ->
        resolve_custom_node(type, source_id, resolution)

      {:ok, %{type: type, id: source_id}} ->
        resolve_generated_node(type, source_id, resolution)

      :error ->
        Absinthe.Resolution.put_result(resolution, {:error, "invalid Relay node id"})
    end
  end

  def resolve_type(%{normalized_event_id: _}), do: :operator_workflow_item
  def resolve_type(%{type: "operator_workflow_item"}), do: :operator_workflow_item

  def resolve_type(value) do
    Projections.graphql_node_type(value) || generated_node_type(value)
  end

  defp resolve_custom_node(:operator_workflow_item, id, resolution) do
    with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {:ok, item} <- Projections.operator_workflow_item(session_context, id) do
      Absinthe.Resolution.put_result(resolution, {:ok, item})
    else
      error -> Absinthe.Resolution.put_result(resolution, Errors.to_absinthe(error))
    end
  end

  defp resolve_custom_node(:graph_relationship_view, id, resolution) do
    with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {:ok, relationship} <-
           OfficeGraph.WorkGraph.graphql_node(
             session_context,
             :graph_relationship_view,
             id
           ) do
      Absinthe.Resolution.put_result(resolution, {:ok, relationship})
    else
      error -> Absinthe.Resolution.put_result(resolution, Errors.to_absinthe(error))
    end
  end

  defp resolve_generated_node(type, id, resolution) do
    resources = resource_map()

    if Map.has_key?(resources, type) do
      resolution
      |> put_in([Access.key(:arguments), Access.key(:id)], Base.encode64("#{type}:#{id}"))
      |> AshGraphql.Graphql.Resolver.resolve_node({resources, @domains})
    else
      Absinthe.Resolution.put_result(resolution, {:error, "invalid Relay node id"})
    end
  end

  defp decode_node_id(id, schema) do
    case AshGraphql.Resource.decode_relay_id(id) do
      {:ok, %{type: type} = decoded}
      when type in @custom_node_types ->
        {:ok, decoded}

      {:ok, %{type: type} = decoded} ->
        if Map.has_key?(resource_map(), type) do
          {:ok, decoded}
        else
          decode_absinthe_node_id(id, schema)
        end

      {:error, _error} ->
        decode_absinthe_node_id(id, schema)
    end
  end

  defp decode_absinthe_node_id(id, schema) do
    case Absinthe.Relay.Node.from_global_id(id, schema) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _error} -> :error
    end
  end

  defp generated_node_type(%{__struct__: resource}) do
    if resource in graphql_resources() do
      AshGraphql.Resource.Info.type(resource)
    end
  end

  defp generated_node_type(_value), do: nil

  defp resource_map do
    Map.new(graphql_resources(), fn resource ->
      {AshGraphql.Resource.Info.type(resource), {Ash.Resource.Info.domain(resource), resource}}
    end)
  end

  defp graphql_resources do
    @domains
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.filter(&(AshGraphql.Resource in Spark.extensions(&1)))
  end
end
