defmodule OfficeGraphWeb.AuthenticationController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Authentication

  @default_return_to "/operator"

  def login(conn, params) do
    return_to = safe_return_to(params["return_to"])

    case Authentication.begin_login(callback_uri(),
           return_to: return_to
         ) do
      {:ok, login} ->
        conn
        |> put_session(:oidc_login_transaction, login.transaction)
        |> redirect(external: login.authorization_uri)

      {:error, _unavailable} ->
        send_resp(conn, 503, "Authentication unavailable")
    end
  end

  def callback(conn, params) do
    transaction = get_session(conn, :oidc_login_transaction)
    conn = delete_session(conn, :oidc_login_transaction)

    complete_callback(conn, params["code"], params["state"], transaction)
  end

  def logout(conn, _params) do
    result =
      case get_session(conn, :human_session_id) do
        session_id when is_binary(session_id) ->
          Authentication.logout(session_id,
            trace_id: trace_id(conn),
            post_logout_redirect_uri: login_uri()
          )

        _missing_session ->
          {:error, :invalid_session}
      end

    case result do
      {:ok, %{provider_logout_uri: uri}} when is_binary(uri) ->
        conn
        |> configure_session(drop: true)
        |> redirect(external: uri)

      {:ok, %{provider_logout_uri: nil}} ->
        conn
        |> configure_session(drop: true)
        |> redirect(to: "/auth/login")

      {:error, :invalid_session} ->
        conn
        |> configure_session(drop: true)
        |> redirect(to: "/auth/login")

      {:error, _revocation_failed} ->
        send_resp(conn, 503, "Logout unavailable")
    end
  end

  defp complete_callback(conn, code, callback_state, transaction) do
    case Authentication.complete_login(code, callback_state, transaction,
           trace_id: trace_id(conn),
           source_surface: "web"
         ) do
      {:ok, completed} ->
        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:human_session_id, completed.session.id)
        |> redirect(to: safe_return_to(Map.get(transaction, :return_to)))

      {:error, _reason} ->
        send_resp(conn, 401, "Authentication failed")
    end
  end

  defp safe_return_to(return_to) when is_binary(return_to) do
    decoded_return_to = fully_decode(return_to)
    uri = URI.parse(decoded_return_to)

    if uri.scheme == nil and uri.host == nil and String.starts_with?(decoded_return_to, "/") and
         not String.starts_with?(decoded_return_to, "//") and
         not String.contains?(decoded_return_to, ["\\", "\r", "\n", <<0>>]) do
      return_to
    else
      @default_return_to
    end
  end

  defp safe_return_to(_return_to), do: @default_return_to

  defp fully_decode(value) do
    case URI.decode(value) do
      ^value -> value
      decoded -> fully_decode(decoded)
    end
  end

  defp callback_uri, do: "#{OfficeGraphWeb.Endpoint.url()}/auth/callback"
  defp login_uri, do: "#{OfficeGraphWeb.Endpoint.url()}/auth/login"

  defp trace_id(conn) do
    case get_resp_header(conn, "x-request-id") do
      [request_id | _rest] -> request_id
      [] -> Ecto.UUID.generate()
    end
  end
end
