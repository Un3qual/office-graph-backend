defmodule OfficeGraphWeb.JsonApi.Common.Errors do
  @moduledoc false

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  alias OfficeGraphWeb.OperatorCommands.Errors

  def render(conn, error, opts \\ []) do
    classification = Errors.classify(error)

    public_error =
      classification.metadata
      |> maybe_put_fields(classification.fields)
      |> Map.merge(%{code: classification.code, detail: classification.detail})

    payload =
      case Keyword.get(opts, :command) do
        nil -> %{error: public_error}
        command -> %{command: command, error: public_error}
      end

    conn
    |> put_status(status(classification, opts))
    |> json(payload)
  end

  defp status(%{category: :authorization}, _opts), do: :forbidden
  defp status(%{category: :availability}, _opts), do: :service_unavailable
  defp status(%{category: :conflict}, _opts), do: :conflict

  defp status(%{category: :not_found, metadata: %{normalized_event_id: _id}}, opts) do
    Keyword.get(opts, :missing_normalized_intake_event_status, :not_found)
  end

  defp status(%{category: :not_found}, opts) do
    Keyword.get(opts, :not_found_status, :unprocessable_entity)
  end

  defp status(_classification, _opts), do: :unprocessable_entity

  defp maybe_put_fields(metadata, []), do: metadata
  defp maybe_put_fields(%{field: _field} = metadata, _fields), do: metadata
  defp maybe_put_fields(metadata, fields), do: Map.put(metadata, :fields, fields)
end
