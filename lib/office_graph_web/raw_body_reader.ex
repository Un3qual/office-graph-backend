defmodule OfficeGraphWeb.RawBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, maybe_append_raw_body(conn, body)}
      {:more, body, conn} -> {:more, body, maybe_append_raw_body(conn, body)}
      {:error, reason} -> {:error, reason}
    end
  end

  def body(conn),
    do: conn.assigns |> Map.get(:raw_body_chunks, []) |> Enum.reverse() |> IO.iodata_to_binary()

  defp append_raw_body(conn, body) do
    Plug.Conn.assign(conn, :raw_body_chunks, [body | Map.get(conn.assigns, :raw_body_chunks, [])])
  end

  defp maybe_append_raw_body(%Plug.Conn{request_path: "/api/v1/webhooks/github"} = conn, body),
    do: append_raw_body(conn, body)

  defp maybe_append_raw_body(conn, _body), do: conn
end
