defmodule OfficeGraph.WorkGraph.Actions.SetupReferenceCatalog do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.WorkGraph.ReferenceCatalog

  @impl true
  def run(_input, _opts, _context) do
    with {:ok, definitions} <- ensure_definitions(),
         {:ok, rule_count} <- ensure_rules(definitions) do
      {:ok, map_size(definitions) + rule_count}
    end
  end

  defp ensure_definitions do
    Enum.reduce_while(ReferenceCatalog.definitions(), {:ok, %{}}, fn attrs, {:ok, definitions} ->
      case ensure(resource(:relationship_definition), attrs) do
        {:ok, definition} ->
          {:cont, {:ok, Map.put(definitions, attrs.key, definition)}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp ensure_rules(definitions) do
    Enum.reduce_while(ReferenceCatalog.rules(), {:ok, 0}, fn
      {definition_key, source_kind, target_kind}, {:ok, count} ->
        attrs = %{
          relationship_definition_id: Map.fetch!(definitions, definition_key).id,
          source_kind: source_kind,
          target_kind: target_kind
        }

        case ensure(resource(:relationship_endpoint_rule), attrs) do
          {:ok, _rule} -> {:cont, {:ok, count + 1}}
          {:error, error} -> {:halt, {:error, error}}
        end
    end)
  end

  defp ensure(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:ensure, attrs)
    |> Ash.create(authorize?: false)
  end

  defp resource(:relationship_definition),
    do: Module.concat([OfficeGraph, WorkGraph, RelationshipDefinition])

  defp resource(:relationship_endpoint_rule),
    do: Module.concat([OfficeGraph, WorkGraph, RelationshipEndpointRule])
end
