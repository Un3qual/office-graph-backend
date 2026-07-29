defmodule OfficeGraph.CommandSupport do
  @moduledoc """
  Shared typed identities and safe errors for public Ash command actions.
  """

  use Boundary, exports: [CommandError, TypedId]

  def normalize_action_result({:ok, result}), do: {:ok, result}

  def normalize_action_result({:error, error}) do
    {:error, unwrap_action_error(error)}
  end

  def normalize_ash_write({:ok, record, _notifications}), do: {:ok, record}
  def normalize_ash_write({:ok, record}), do: {:ok, record}
  def normalize_ash_write({:error, error}), do: {:error, error}

  def record_without_notifications({record, _notifications}), do: record
  def record_without_notifications(record), do: record

  defp unwrap_action_error(%Ash.Error.Unknown{
         errors: [
           %Ash.Error.Unknown.UnknownError{
             error: nil,
             value: [{reason, detail}]
           }
         ]
       })
       when is_atom(reason),
       do: {reason, detail}

  defp unwrap_action_error(error), do: error
end
