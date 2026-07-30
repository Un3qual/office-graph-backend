defmodule OfficeGraphWeb.WorkOSWebhookController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.EnterpriseIdentity
  alias OfficeGraphWeb.RawBodyReader

  def create(conn, _params) do
    headers = %{"workos-signature" => header(conn, "workos-signature")}

    case EnterpriseIdentity.accept_webhook(headers, RawBodyReader.body(conn)) do
      {:ok, status} ->
        conn
        |> put_status(:accepted)
        |> json(%{status: Atom.to_string(status)})

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value] -> value
      _other -> nil
    end
  end

  defp render_error(conn, :invalid_signature),
    do: error(conn, :unauthorized, "invalid_signature")

  defp render_error(conn, :unknown_directory),
    do: error(conn, :not_found, "unknown_directory")

  defp render_error(conn, :event_conflict),
    do: error(conn, :conflict, "event_conflict")

  defp render_error(conn, :unsupported_event),
    do: error(conn, :unprocessable_entity, "unsupported_event")

  defp render_error(conn, :invalid_delivery),
    do: error(conn, :unprocessable_entity, "invalid_delivery")

  defp render_error(conn, _reason),
    do: error(conn, :service_unavailable, "receipt_unavailable")

  defp error(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, detail: "WorkOS delivery was not accepted."}})
  end
end
