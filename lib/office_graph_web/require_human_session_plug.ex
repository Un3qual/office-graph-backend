defmodule OfficeGraphWeb.RequireHumanSessionPlug do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Ash.PlugHelpers.get_actor(conn) do
      nil ->
        conn
        |> redirect(to: login_path(conn))
        |> halt()

      _session_context ->
        conn
    end
  end

  defp login_path(conn) do
    query = URI.encode_query(%{"return_to" => request_target(conn)})
    "/auth/login?#{query}"
  end

  defp request_target(%{query_string: ""} = conn), do: conn.request_path
  defp request_target(conn), do: "#{conn.request_path}?#{conn.query_string}"
end
