defmodule OfficeGraph.GitHubIntegration.StorageResult do
  @moduledoc false

  @storage_exceptions [
    Ash.Error.Forbidden,
    Ash.Error.Framework,
    Ash.Error.Invalid,
    Ash.Error.Unknown,
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error,
    RuntimeError
  ]

  def run(fun) when is_function(fun, 0) do
    fun.()
    |> normalize_result()
  rescue
    _error in @storage_exceptions -> unavailable()
  catch
    :exit, _reason -> unavailable()
  end

  defp normalize_result(:ok), do: :ok
  defp normalize_result({:ok, result}), do: {:ok, result}

  defp normalize_result({:error, reason} = error)
       when reason in [:forbidden, :integration_storage_unavailable],
       do: error

  defp normalize_result({:error, _storage_error}), do: unavailable()

  defp unavailable, do: {:error, :integration_storage_unavailable}
end
