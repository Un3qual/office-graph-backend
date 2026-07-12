defmodule OfficeGraph.Runs.Changes.ScopedRead do
  @moduledoc false

  require Ash.Query

  def fetch(resource, id, organization_id, workspace_id, field, missing_message) do
    fetch_with_lock(
      resource,
      id,
      organization_id,
      workspace_id,
      field,
      missing_message,
      false
    )
  end

  def fetch_locked(resource, id, organization_id, workspace_id, field, missing_message) do
    fetch_with_lock(
      resource,
      id,
      organization_id,
      workspace_id,
      field,
      missing_message,
      true
    )
  end

  defp fetch_with_lock(
         _resource,
         nil,
         _organization_id,
         _workspace_id,
         field,
         missing_message,
         _lock?
       ) do
    {:error, field, missing_message}
  end

  defp fetch_with_lock(
         _resource,
         _id,
         nil,
         _workspace_id,
         _field,
         _missing_message,
         _lock?
       ) do
    {:error, :organization_id, "target organization_id and workspace_id are required"}
  end

  defp fetch_with_lock(
         _resource,
         _id,
         _organization_id,
         nil,
         _field,
         _missing_message,
         _lock?
       ) do
    {:error, :workspace_id, "target organization_id and workspace_id are required"}
  end

  defp fetch_with_lock(resource, id, org_id, workspace_id, field, missing_message, lock?) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> maybe_lock(lock?)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{organization_id: ^org_id, workspace_id: ^workspace_id} = record} ->
        {:ok, record}

      {:ok, _missing_or_cross_scope} ->
        {:error, field, missing_message}

      {:error, error} ->
        {:error, field, "#{field} lookup failed: #{format_lookup_error(error)}"}
    end
  end

  defp maybe_lock(query, true), do: Ash.Query.lock(query, :for_update)
  defp maybe_lock(query, false), do: query

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)
end
