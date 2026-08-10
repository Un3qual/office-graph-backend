defmodule OfficeGraph.NodeConversations.ActionSupport do
  @moduledoc false

  alias OfficeGraph.CommandSupport

  @rollback_marker :node_conversation_action_error

  @storage_exceptions [
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error
  ]

  def rollback(resource, error) do
    Ash.DataLayer.rollback(resource, {@rollback_marker, error})
  end

  def run(fun) when is_function(fun, 0) do
    fun.()
    |> CommandSupport.normalize_action_result()
    |> case do
      {:error, {@rollback_marker, error}} -> {:error, error}
      result -> result
    end
  rescue
    _error in @storage_exceptions -> {:error, :integration_storage_unavailable}
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, [_pool, _opts]}} ->
      {:error, :integration_storage_unavailable}
  end
end
