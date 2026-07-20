defmodule OfficeGraph.AgentRuntime.StorageResult do
  @moduledoc false

  @storage_exceptions [
    Ash.Error.Forbidden,
    Ash.Error.Framework,
    Ash.Error.Invalid,
    Ash.Error.Unknown,
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error
  ]

  def run(fun) when is_function(fun, 0) do
    fun.()
  rescue
    _error in @storage_exceptions -> {:error, :integration_storage_unavailable}
  catch
    :exit, _reason -> {:error, :integration_storage_unavailable}
  end
end
