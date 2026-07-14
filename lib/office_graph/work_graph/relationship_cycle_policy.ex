defmodule OfficeGraph.WorkGraph.RelationshipCyclePolicy do
  @moduledoc false

  alias OfficeGraph.Repo

  @max_cycle_nodes 10_000

  def lock_and_validate!(
        %{cycle_policy: "forbid"} = definition,
        organization_id,
        request
      ) do
    lock_definition!(organization_id, definition.id)

    case reachable?(
           organization_id,
           definition.id,
           request.target_item_id,
           request.source_item_id
         ) do
      false -> :ok
      true -> Repo.rollback({:relationship_cycle, definition.key})
      :limit -> Repo.rollback({:relationship_cycle_check_limit, definition.key})
    end
  end

  def lock_and_validate!(%{cycle_policy: "allow"}, _organization_id, _request), do: :ok

  defp lock_definition!(organization_id, definition_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      organization_id <> ":" <> definition_id
    ])
  end

  defp reachable?(organization_id, definition_id, target_item_id, source_item_id) do
    %{rows: [[source_reached?, limit_exceeded?]]} =
      Repo.query!(
        """
        WITH RECURSIVE reachable(item_id, path) AS (
          SELECT $3::text::uuid, ARRAY[$3::text::uuid]
          UNION ALL
          SELECT relationships.target_item_id, reachable.path || relationships.target_item_id
          FROM reachable
          JOIN graph_relationships AS relationships
            ON relationships.source_item_id = reachable.item_id
          WHERE relationships.organization_id = $1::text::uuid
            AND relationships.definition_id = $2::text::uuid
            AND relationships.lifecycle = 'active'
            AND NOT relationships.target_item_id = ANY(reachable.path)
        ), bounded AS (
          SELECT item_id FROM reachable LIMIT $5
        )
        SELECT
          COALESCE(bool_or(item_id = $4::text::uuid), false),
          count(*) > $6
        FROM bounded
        """,
        [
          organization_id,
          definition_id,
          target_item_id,
          source_item_id,
          @max_cycle_nodes + 1,
          @max_cycle_nodes
        ]
      )

    cond do
      source_reached? -> true
      limit_exceeded? -> :limit
      true -> false
    end
  end
end
