defmodule OfficeGraph.WorkGraph.RelationshipCyclePolicy do
  @moduledoc false

  alias OfficeGraph.WorkGraph.{
    CommandSupport,
    GraphRelationship,
    RelationshipDefinition
  }

  require Ash.Query

  @max_cycle_nodes 10_000

  def lock_and_validate!(
        %{cycle_policy: "forbid"} = definition,
        organization_id,
        request
      ) do
    lock_definition!(definition.id)

    case reachable?(
           organization_id,
           definition.id,
           request.target_item_id,
           request.source_item_id
         ) do
      false -> :ok
      true -> CommandSupport.rollback({:relationship_cycle, definition.key})
      :limit -> CommandSupport.rollback({:relationship_cycle_check_limit, definition.key})
    end
  end

  def lock_and_validate!(%{cycle_policy: "allow"}, _organization_id, _request), do: :ok

  defp lock_definition!(definition_id) do
    RelationshipDefinition
    |> Ash.Query.filter(id == ^definition_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %RelationshipDefinition{}} ->
        :ok

      {:ok, nil} ->
        CommandSupport.rollback({:relationship_definition_not_found, definition_id})

      {:error, error} ->
        CommandSupport.rollback(error)
    end
  end

  defp reachable?(_organization_id, _definition_id, item_id, item_id), do: true

  defp reachable?(organization_id, definition_id, target_item_id, source_item_id) do
    traverse(
      organization_id,
      definition_id,
      source_item_id,
      [target_item_id],
      MapSet.new([target_item_id])
    )
  end

  defp traverse(_organization_id, _definition_id, _source_item_id, [], _visited), do: false

  defp traverse(organization_id, definition_id, source_item_id, frontier, visited) do
    remaining = @max_cycle_nodes - MapSet.size(visited)

    if remaining <= 0 do
      :limit
    else
      edges = outgoing_edges(organization_id, definition_id, frontier, remaining + 1)
      targets = Enum.map(edges, & &1.target_item_id)

      cond do
        source_item_id in targets ->
          true

        length(edges) > remaining ->
          :limit

        true ->
          next_frontier =
            targets
            |> Enum.uniq()
            |> Enum.reject(&MapSet.member?(visited, &1))

          next_visited = Enum.reduce(next_frontier, visited, &MapSet.put(&2, &1))

          if MapSet.size(next_visited) > @max_cycle_nodes do
            :limit
          else
            traverse(
              organization_id,
              definition_id,
              source_item_id,
              next_frontier,
              next_visited
            )
          end
      end
    end
  end

  defp outgoing_edges(organization_id, definition_id, frontier, limit) do
    GraphRelationship
    |> Ash.Query.filter(
      organization_id == ^organization_id and definition_id == ^definition_id and
        lifecycle == "active" and source_item_id in ^frontier
    )
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, relationships} -> relationships
      {:error, error} -> CommandSupport.rollback(error)
    end
  end
end
