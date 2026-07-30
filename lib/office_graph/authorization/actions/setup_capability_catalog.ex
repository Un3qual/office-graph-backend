defmodule OfficeGraph.Authorization.Actions.SetupCapabilityCatalog do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Authorization.ReferenceCatalog

  @impl true
  def run(_input, _opts, _context) do
    ReferenceCatalog.recognized_capability_keys()
    |> Enum.reduce_while({:ok, 0}, fn key, {:ok, count} ->
      case ensure(key) do
        {:ok, _capability} -> {:cont, {:ok, count + 1}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp ensure(key) do
    [OfficeGraph, Authorization, Capability]
    |> Module.concat()
    |> Ash.Changeset.for_create(:ensure, %{key: key, description: key})
    |> Ash.create(authorize?: false)
  end
end
