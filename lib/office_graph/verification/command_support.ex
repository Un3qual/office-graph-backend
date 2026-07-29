defmodule OfficeGraph.Verification.CommandSupport do
  @moduledoc false

  alias OfficeGraph.{Audit, Revisions}

  require Ash.Query

  def fetch_optional_scoped(_resource, _session_context, nil), do: {:ok, nil}

  def fetch_optional_scoped(resource, session_context, id) do
    fetch_scoped(resource, session_context, id)
  end

  def fetch_scoped(resource, session_context, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:error, {:not_found, resource, id}}

      {:ok, record} ->
        case validate_scope(session_context, record) do
          :ok -> {:ok, record}
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  def trace!(operation, action, resource_type, resource_id) do
    Audit.record!(operation, action, resource_type, resource_id)
    Revisions.record!(operation, resource_type, resource_id, action, action)
  end

  def validate_scope(session_context, record) do
    if record.organization_id == session_context.organization_id and
         record.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
