defmodule OfficeGraph.Verification.CommandSupport do
  @moduledoc false

  alias OfficeGraph.Operations
  alias OfficeGraph.Repo
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

  def fetch_scoped!(resource, session_context, id) do
    case fetch_scoped(resource, session_context, id) do
      {:ok, record} -> record
      {:error, error} -> Repo.rollback(error)
    end
  end

  def lock_operation!(operation_id) do
    case Operations.lock_operation(operation_id) do
      {:ok, operation} -> operation
      {:error, error} -> Repo.rollback(error)
    end
  end

  def lock_optional_scoped!(_resource, _session_context, nil), do: nil

  def lock_optional_scoped!(resource, session_context, id) do
    lock_scoped!(resource, session_context, id)
  end

  def lock_scoped!(resource, session_context, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        Repo.rollback({:not_found, resource, id})

      {:ok, record} ->
        validate_scope!(session_context, record)
        record

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  def normalize_transaction_result({:ok, result}), do: {:ok, result}
  def normalize_transaction_result({:error, error}), do: {:error, error}

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

  def validate_scope!(session_context, record) do
    case validate_scope(session_context, record) do
      :ok -> :ok
      {:error, error} -> Repo.rollback(error)
    end
  end
end
