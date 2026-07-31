defmodule OfficeGraph.AgentRuntime.Actions.SetupReferenceCatalog do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.AgentRuntime.ReferenceCatalog

  @impl true
  def run(_input, _opts, _context) do
    ReferenceCatalog.definitions()
    |> Enum.reduce_while({:ok, 0}, fn attrs, {:ok, count} ->
      case ensure(attrs) do
        {:ok, _definition} -> {:cont, {:ok, count + 1}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp ensure(attrs) do
    [OfficeGraph, AgentRuntime, AgentDefinition]
    |> Module.concat()
    |> Ash.Changeset.for_create(:ensure, attrs)
    |> Ash.create(authorize?: false)
  end
end
