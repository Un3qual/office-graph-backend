defmodule OfficeGraphWeb.GraphQL.Common.NodeResolver do
  @moduledoc false

  alias OfficeGraph.Projections
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.RequestSession

  @domains [
    OfficeGraph.WorkGraph.Domain,
    OfficeGraph.WorkPackets.Domain,
    OfficeGraph.Runs.Domain,
    OfficeGraph.Integrations.Domain,
    OfficeGraph.ProposedChanges.Domain,
    OfficeGraph.AgentRuntime.Domain,
    OfficeGraph.NodeConversations.Domain,
    OfficeGraph.GitHubIntegration.Domain
  ]

  @custom_node_types [
    :github_integration_health,
    :graph_relationship_view,
    :operator_packet_workspace,
    :operator_run_conversation,
    :operator_run_state,
    :operator_workflow_item
  ]

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

  def resolve_type(%{type: "operator_workflow_item"}), do: :operator_workflow_item
  def resolve_type(%{type: "github_integration_health"}), do: :github_integration_health
  def resolve_type(%{type: "operator_packet_workspace"}), do: :operator_packet_workspace
  def resolve_type(%{type: "operator_run_conversation"}), do: :operator_run_conversation
  def resolve_type(%{type: "operator_run_state"}), do: :operator_run_state

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

  defp resolve_custom_node(:operator_packet_workspace, id, resolution) do
    with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {:ok, workspace} <- Projections.packet_workspace(session_context, id) do
      Absinthe.Resolution.put_result(resolution, {:ok, workspace})
    else
      error -> Absinthe.Resolution.put_result(resolution, Errors.to_absinthe(error))
    end
  end

  defp resolve_custom_node(:operator_run_state, id, resolution) do
    with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {:ok, run_state} <- Projections.operator_run_state(session_context, id) do
      Absinthe.Resolution.put_result(resolution, {:ok, run_state})
    else
      error -> Absinthe.Resolution.put_result(resolution, Errors.to_absinthe(error))
    end
  end

  defp resolve_custom_node(:github_integration_health, id, resolution) do
    with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {:ok, health} <- Projections.integration_health(session_context, id, limit: 20) do
      Absinthe.Resolution.put_result(resolution, {:ok, health})
    else
      error -> Absinthe.Resolution.put_result(resolution, Errors.to_absinthe(error))
    end
  end

  defp resolve_custom_node(:operator_run_conversation, id, resolution) do
    with {:ok, run_id, graph_item_id} <- decode_run_conversation_id(id),
         {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
         {:ok, conversation} <-
           OfficeGraph.NodeConversations.project(session_context, run_id, graph_item_id) do
      Absinthe.Resolution.put_result(resolution, {:ok, conversation})
    else
      {:error, :invalid_node_id} ->
        Absinthe.Resolution.put_result(resolution, {:error, "invalid Relay node id"})

      error ->
        Absinthe.Resolution.put_result(resolution, Errors.to_absinthe(error))
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

  defp decode_run_conversation_id(id) do
    with [run_id, graph_item_id] <- String.split(id, ":", parts: 2),
         {:ok, run_id} <- Ecto.UUID.cast(run_id),
         {:ok, graph_item_id} <- Ecto.UUID.cast(graph_item_id) do
      {:ok, run_id, graph_item_id}
    else
      _invalid -> {:error, :invalid_node_id}
    end
  end

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
