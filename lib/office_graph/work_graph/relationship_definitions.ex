defmodule OfficeGraph.WorkGraph.RelationshipDefinitions do
  @moduledoc false

  alias OfficeGraph.WorkGraph.RelationshipDefinition

  require Ash.Query

  @spec fetch_by_key(String.t()) ::
          {:ok, RelationshipDefinition.t()}
          | {:error, {:unknown_relationship_definition, String.t()}}
          | {:error, term()}
  def fetch_by_key(key) when is_binary(key) do
    RelationshipDefinition
    |> Ash.Query.filter(key == ^key and lifecycle == "active")
    |> Ash.Query.load(:endpoint_rules)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, {:unknown_relationship_definition, key}}
      result -> result
    end
  end
end
