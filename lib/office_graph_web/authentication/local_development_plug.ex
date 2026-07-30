defmodule OfficeGraphWeb.Authentication.LocalDevelopmentPlug do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias OfficeGraph.Authentication

  @loopback_addresses [
    {127, 0, 0, 1},
    {0, 0, 0, 0, 0, 0, 0, 1}
  ]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if available?(conn) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not found")
      |> halt()
    end
  end

  def available?(%Plug.Conn{remote_ip: remote_ip}) do
    Authentication.local_development_enabled?() and remote_ip in @loopback_addresses
  end
end
