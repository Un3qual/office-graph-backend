defmodule OfficeGraph.AgentRuntime.StorageResult do
  @moduledoc false

  @permanent_exceptions [
    Ash.Error.Forbidden,
    Ash.Error.Invalid
  ]

  @storage_exceptions [
    Ash.Error.Framework,
    Ash.Error.Unknown,
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error
  ]

  def run(fun) when is_function(fun, 0) do
    fun.()
  rescue
    error in @permanent_exceptions -> {:error, error}
    _error in @storage_exceptions -> {:error, :integration_storage_unavailable}
  catch
    :exit, _reason -> {:error, :integration_storage_unavailable}
  end
end
