defmodule OfficeGraph.Runs.Changes.ScopedRead do
  @moduledoc false

  require Ash.Query

  def fetch(_resource, nil, _organization_id, _workspace_id, field, missing_message) do
    {:error, field, missing_message}
  end

  def fetch(_resource, _id, nil, _workspace_id, _field, _missing_message) do
    {:error, :organization_id, "target organization_id and workspace_id are required"}
  end

  def fetch(_resource, _id, _organization_id, nil, _field, _missing_message) do
    {:error, :workspace_id, "target organization_id and workspace_id are required"}
  end

  def fetch(resource, id, organization_id, workspace_id, field, missing_message) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id} = record} ->
        {:ok, record}

      {:ok, _missing_or_cross_scope} ->
        {:error, field, missing_message}

      {:error, error} ->
        {:error, field, "#{field} lookup failed: #{format_lookup_error(error)}"}
    end
  end

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)
end
