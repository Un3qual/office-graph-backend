defmodule OfficeGraphWeb.SameOriginRequestPlug do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @unsafe_methods ~w(POST PUT PATCH DELETE)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method} = conn, _opts) when method in @unsafe_methods do
    if is_binary(get_session(conn, :human_session_id)) and not same_origin?(conn) do
      conn
      |> send_resp(403, "Cross-origin request forbidden")
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp same_origin?(conn) do
    case get_req_header(conn, "origin") do
      [origin] -> origin_tuple(origin) == origin_tuple(OfficeGraphWeb.Endpoint.url())
      [] -> fetch_site_allows_request?(conn)
      _multiple_origins -> false
    end
  end

  defp fetch_site_allows_request?(conn) do
    get_req_header(conn, "sec-fetch-site") in [[], ["same-origin"], ["none"]]
  end

  defp origin_tuple(origin) do
    case URI.parse(origin) do
      %URI{
        scheme: scheme,
        host: host,
        port: port,
        path: path,
        query: nil,
        fragment: nil,
        userinfo: nil
      }
      when is_binary(scheme) and is_binary(host) and path in [nil, ""] ->
        {String.downcase(scheme), String.downcase(host), port || URI.default_port(scheme)}

      _invalid_origin ->
        :invalid
    end
  end
end
