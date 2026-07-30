defmodule OfficeGraphWeb.AuthenticationController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Authentication
  alias OfficeGraphWeb.Authentication.{LocalDevelopmentPlug, ReturnTarget}

  @logged_out_path "/auth/logged-out"

  def login(conn, params) do
    return_to = ReturnTarget.safe(params["return_to"])

    if params["provider"] == "oidc" or not LocalDevelopmentPlug.available?(conn) do
      begin_oidc_login(conn, return_to)
    else
      render_local_development_login(conn, return_to)
    end
  end

  defp begin_oidc_login(conn, return_to) do
    case Authentication.begin_login(callback_uri(),
           return_to: return_to,
           trace_id: trace_id(conn),
           source_surface: "web"
         ) do
      {:ok, login} ->
        conn
        |> put_session(:oidc_login_transaction, login.transaction)
        |> redirect(external: login.authorization_uri)

      {:error, _unavailable} ->
        plain_text_response(conn, 503, "Authentication unavailable")
    end
  end

  def callback(conn, params) do
    transaction = get_session(conn, :oidc_login_transaction)
    conn = delete_session(conn, :oidc_login_transaction)

    complete_callback(conn, params["code"], params["state"], transaction)
  end

  def workos_login(conn, %{"connection_id" => connection_id} = params) do
    return_to = ReturnTarget.safe(params["return_to"])

    case Authentication.begin_workos_login(connection_id, workos_callback_uri(),
           return_to: return_to,
           trace_id: trace_id(conn),
           source_surface: "web"
         ) do
      {:ok, login} ->
        conn
        |> put_session(:oidc_login_transaction, login.transaction)
        |> redirect(external: login.authorization_uri)

      {:error, _unavailable} ->
        plain_text_response(conn, 503, "Authentication unavailable")
    end
  end

  def workos_callback(conn, params) do
    transaction = get_session(conn, :oidc_login_transaction)
    conn = delete_session(conn, :oidc_login_transaction)

    complete_workos_callback(conn, params["code"], params["state"], transaction)
  end

  def logout(conn, _params) do
    result =
      case get_session(conn, :human_session_id) do
        session_id when is_binary(session_id) ->
          Authentication.logout(session_id,
            trace_id: trace_id(conn),
            post_logout_redirect_uri: logged_out_uri()
          )

        _missing_session ->
          {:error, :invalid_session}
      end

    case result do
      {:ok, %{provider_logout_uri: uri}} when is_binary(uri) ->
        conn
        |> configure_session(drop: true)
        |> redirect(external: uri)

      {:ok, %{authentication_method: "local_development", provider_logout_uri: nil}} ->
        conn
        |> configure_session(drop: true)
        |> redirect(to: "/auth/login")

      {:ok, %{provider_logout_uri: nil}} ->
        conn
        |> configure_session(drop: true)
        |> redirect(to: @logged_out_path)

      {:error, :invalid_session} ->
        conn
        |> configure_session(drop: true)
        |> redirect(to: @logged_out_path)

      {:error, _revocation_failed} ->
        plain_text_response(conn, 503, "Logout unavailable")
    end
  end

  def logged_out(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(
      200,
      """
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Signed out · Office Graph</title>
        </head>
        <body>
          <main>
            <h1>You are signed out</h1>
            <p><a href="/auth/login">Sign in</a></p>
          </main>
        </body>
      </html>
      """
    )
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
        |> redirect(to: ReturnTarget.safe(Map.get(transaction, :return_to)))

      {:error, reason} ->
        authentication_error_response(conn, reason)
    end
  end

  defp complete_workos_callback(conn, code, callback_state, transaction) do
    case Authentication.complete_workos_login(code, callback_state, transaction,
           trace_id: trace_id(conn),
           source_surface: "web"
         ) do
      {:ok, completed} ->
        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:human_session_id, completed.session.id)
        |> redirect(to: ReturnTarget.safe(Map.get(transaction, :return_to)))

      {:error, reason} ->
        authentication_error_response(conn, reason)
    end
  end

  defp authentication_error_response(conn, reason) do
    if Authentication.transient_storage_error?(reason) do
      plain_text_response(conn, 503, "Authentication unavailable")
    else
      plain_text_response(conn, 401, "Authentication failed")
    end
  end

  defp render_local_development_login(conn, return_to) do
    conn =
      Plug.CSRFProtection.call(
        conn,
        Plug.CSRFProtection.init([])
      )

    csrf_token = Plug.CSRFProtection.get_csrf_token()
    fixture_forms = local_development_fixture_forms(csrf_token)

    oidc_option =
      if Authentication.oidc_available?() do
        ~s(<p><a href="/auth/login?provider=oidc">Use optional Authentik OIDC</a></p>)
      else
        ""
      end

    conn
    |> put_session(:authentication_return_to, return_to)
    |> put_resp_content_type("text/html")
    |> send_resp(
      200,
      """
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Local development sign in · Office Graph</title>
        </head>
        <body>
          <main>
            <h1>Local development sign in</h1>
            <p>Select a pre-seeded identity. These sessions use normal Office Graph authorization.</p>
            <div>#{fixture_forms}</div>
            #{oidc_option}
          </main>
        </body>
      </html>
      """
    )
  end

  defp local_development_fixture_forms(csrf_token) do
    escaped_token = Plug.HTML.html_escape(csrf_token)

    Authentication.local_development_fixtures()
    |> Enum.map_join("\n", fn fixture ->
      key = Plug.HTML.html_escape(fixture.key)
      label = Plug.HTML.html_escape(fixture.display_name)

      """
      <form method="post" action="/auth/development/login">
        <input type="hidden" name="_csrf_token" value="#{escaped_token}">
        <button name="fixture" type="submit" value="#{key}">#{label}</button>
      </form>
      """
    end)
  end

  defp plain_text_response(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
  end

  defp callback_uri, do: "#{OfficeGraphWeb.Endpoint.url()}/auth/callback"
  defp workos_callback_uri, do: "#{OfficeGraphWeb.Endpoint.url()}/auth/workos/callback"
  defp logged_out_uri, do: "#{OfficeGraphWeb.Endpoint.url()}#{@logged_out_path}"

  defp trace_id(conn) do
    case get_resp_header(conn, "x-request-id") do
      [request_id | _rest] -> request_id
      [] -> Ecto.UUID.generate()
    end
  end
end
