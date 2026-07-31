defmodule OfficeGraphWeb.Authentication.LocalDevelopmentController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Authentication
  alias OfficeGraphWeb.Authentication.ReturnTarget

  def login(conn, %{"fixture" => fixture_key}) do
    select_fixture(conn, fixture_key)
  end

  def login(conn, _params) do
    error_response(conn, 400, "Invalid local identity selection.")
  end

  def switch(conn, %{"fixture" => fixture_key}) do
    select_fixture(conn, fixture_key)
  end

  def switch(conn, _params) do
    error_response(conn, 400, "Invalid local identity selection.")
  end

  defp select_fixture(conn, fixture_key) do
    recognized_fixture? =
      match?({:ok, _fixture}, Authentication.local_development_fixture(fixture_key))

    case revoke_current_session(conn) do
      {:ok, prepared_conn} ->
        complete_fixture_selection(prepared_conn, fixture_key, recognized_fixture?)

      {:error, :revocation_unavailable} ->
        error_response(conn, 503, "Identity switching is temporarily unavailable.")
    end
  end

  defp complete_fixture_selection(conn, fixture_key, recognized_fixture?) do
    case Authentication.complete_local_development_login(fixture_key,
           trace_id: trace_id(conn),
           source_surface: "web"
         ) do
      {:ok, completed} ->
        return_to =
          conn
          |> get_session(:authentication_return_to)
          |> ReturnTarget.safe()

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:human_session_id, completed.session.id)
        |> redirect(to: return_to)

      {:error, reason} ->
        conn
        |> clear_revoked_session()
        |> authentication_error_response(reason, recognized_fixture?)
    end
  end

  defp revoke_current_session(conn) do
    case get_session(conn, :human_session_id) do
      session_id when is_binary(session_id) ->
        case Authentication.logout(session_id, trace_id: trace_id(conn)) do
          {:ok, _logout} -> {:ok, assign(conn, :local_development_session_revoked, true)}
          {:error, :invalid_session} -> {:ok, delete_session(conn, :human_session_id)}
          {:error, _storage_error} -> {:error, :revocation_unavailable}
        end

      _missing_session ->
        {:ok, conn}
    end
  end

  defp clear_revoked_session(%{assigns: %{local_development_session_revoked: true}} = conn) do
    delete_session(conn, :human_session_id)
  end

  defp clear_revoked_session(conn), do: conn

  defp authentication_error_response(conn, :local_development_fixture_missing, true) do
    error_response(
      conn,
      503,
      "Local development identities are unavailable. Run mix demo.seed and try again."
    )
  end

  defp authentication_error_response(
         conn,
         :local_development_fixture_missing,
         false
       ) do
    error_response(conn, 400, "Invalid local identity selection.")
  end

  defp authentication_error_response(conn, :identity_disabled, _recognized_fixture?) do
    error_response(conn, 403, "This local development identity is disabled.")
  end

  defp authentication_error_response(conn, :authentication_unavailable, _recognized_fixture?) do
    error_response(conn, 404, "Local development authentication is unavailable.")
  end

  defp authentication_error_response(conn, reason, _recognized_fixture?) do
    if Authentication.transient_storage_error?(reason) do
      error_response(conn, 503, "Authentication is temporarily unavailable.")
    else
      error_response(conn, 401, "Authentication failed.")
    end
  end

  defp error_response(conn, status, message) do
    escaped_message = Plug.HTML.html_escape(message)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(
      status,
      """
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Authentication · Office Graph</title>
        </head>
        <body>
          <main>
            <h1>Authentication</h1>
            <p>#{escaped_message}</p>
            <p><a href="/auth/login">Return to sign in</a></p>
          </main>
        </body>
      </html>
      """
    )
  end

  defp trace_id(conn) do
    case get_resp_header(conn, "x-request-id") do
      [request_id | _rest] -> request_id
      [] -> Ecto.UUID.generate()
    end
  end
end
