defmodule OfficeGraphWeb.AuthenticationControllerTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Authentication.OidcClient.TestAdapter
  alias OfficeGraph.{Foundation, Identity}
  alias OfficeGraph.Identity.AuthenticationEvent
  alias OfficeGraph.Tenancy.Organization

  @moduletag :unauthenticated

  @issuer "https://authentik.office-graph.local/application/o/office-graph/"
  @redirect_uri "http://localhost:4002/auth/callback"

  setup do
    original_config = Application.get_env(:office_graph, :human_oidc)
    original_client = Application.get_env(:office_graph, :human_oidc_client)

    Application.put_env(:office_graph, :human_oidc_client, TestAdapter)

    Application.put_env(:office_graph, :human_oidc,
      issuer: @issuer,
      client_id: "office-graph-web-test",
      client_secret: "test-client-secret",
      account_linking_policy: :verified_email_existing_principal,
      session_ttl_seconds: 3_600
    )

    TestAdapter.put(%{
      authorization_uri: {:ok, "https://authentik.office-graph.local/authorize"},
      logout_uri: {:error, :unsupported}
    })

    on_exit(fn ->
      restore_env(:human_oidc, original_config)
      restore_env(:human_oidc_client, original_client)
    end)

    :ok
  end

  test "login stores the bounded OIDC transaction and redirects to Authentik", %{conn: conn} do
    conn = get(conn, ~p"/auth/login?return_to=/runs")

    assert redirected_to(conn) == "https://authentik.office-graph.local/authorize"

    assert %{
             state: state,
             nonce: nonce,
             pkce_verifier: verifier,
             return_to: "/runs"
           } = get_session(conn, :oidc_login_transaction)

    assert is_binary(state) and state != ""
    assert is_binary(nonce) and nonce != ""
    assert is_binary(verifier) and verifier != ""
  end

  test "login rejects external return targets", %{conn: conn} do
    conn = get(conn, ~p"/auth/login?return_to=https://attacker.example/capture")

    assert get_session(conn, :oidc_login_transaction).return_to == "/operator"
  end

  test "login fails closed when the provider is unavailable", %{conn: conn} do
    Application.put_env(:office_graph, :human_oidc, issuer: @issuer)

    conn = get(conn, ~p"/auth/login")

    assert response(conn, 503) == "Authentication unavailable"
    refute get_session(conn, :oidc_login_transaction)
  end

  test "callback consumes a mismatched state without calling the provider", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{oidc_login_transaction: login_transaction()})
      |> get(~p"/auth/callback?code=authorization-code&state=wrong")

    assert response(conn, 401) == "Authentication failed"
    refute get_session(conn, :oidc_login_transaction)
    assert TestAdapter.calls(:exchange) == 0

    assert [event] = Ash.read!(AuthenticationEvent, authorize?: false)
    assert event.event == "login"
    assert event.result == "rejected"
    assert event.reason == "invalid_login_transaction"
  end

  test "callback issues a durable session and rotates the cookie to its id only", %{conn: conn} do
    bootstrap = bootstrap("callback")

    TestAdapter.put(%{
      exchange: {:ok, claims(bootstrap.principal.email, "callback-subject")}
    })

    conn =
      conn
      |> Plug.Test.init_test_session(%{oidc_login_transaction: login_transaction()})
      |> get(~p"/auth/callback?code=authorization-code&state=state")

    assert redirected_to(conn) == "/operator"
    assert %{"human_session_id" => session_id} = get_session(conn)
    assert Map.keys(get_session(conn)) == ["human_session_id"]
    assert {:ok, session_context} = Identity.resolve_human_session(session_id)
    assert session_context.principal_id == bootstrap.principal.id

    set_cookie = conn |> get_resp_header("set-cookie") |> Enum.join(";")
    assert set_cookie =~ "HttpOnly"
    assert set_cookie =~ "SameSite=Lax"
  end

  test "callback provider failure leaves no authenticated session", %{conn: conn} do
    TestAdapter.put(%{exchange: {:error, :provider_down}})

    conn =
      conn
      |> Plug.Test.init_test_session(%{oidc_login_transaction: login_transaction()})
      |> get(~p"/auth/callback?code=authorization-code&state=state")

    assert response(conn, 401) == "Authentication failed"
    refute get_session(conn, :oidc_login_transaction)
    refute get_session(conn, :human_session_id)
  end

  test "logout revokes locally even when provider logout is unsupported", %{conn: conn} do
    issued = issue_session("logout")

    conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> post(~p"/auth/logout")

    assert redirected_to(conn) == "/auth/login"
    assert conn.private.plug_session_info == :drop
    assert {:error, :invalid_session} = Identity.resolve_human_session(issued.session.id)
  end

  test "product pages redirect anonymous requests to login", %{conn: conn} do
    conn = get(conn, ~p"/operator")

    assert conn.status == 302

    location =
      conn
      |> get_resp_header("location")
      |> List.first()
      |> URI.parse()

    assert location.path == "/auth/login"
    assert URI.decode_query(location.query)["return_to"] == "/operator"
  end

  test "product pages reject and clear a revoked durable session", %{conn: conn} do
    issued = issue_session("revoked-product")
    assert :ok = Identity.revoke_human_session(issued.session.id, trace_id: "revoked-product")

    conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> get(~p"/operator")

    assert conn.status == 302
    refute get_session(conn, :human_session_id)
  end

  test "anonymous GraphQL requests do not bootstrap a local owner", %{conn: conn} do
    assert Ash.count!(Organization, authorize?: false) == 0

    conn =
      post(conn, ~p"/graphql", %{
        query: "{ listSignals { edges { node { id } } } }"
      })

    assert json_response(conn, 200)["errors"]
    assert Ash.count!(Organization, authorize?: false) == 0
  end

  defp issue_session(prefix) do
    bootstrap = bootstrap(prefix)

    {:ok, linked} =
      Identity.reconcile_oidc_identity(
        claims(bootstrap.principal.email, "#{prefix}-subject"),
        provider: "authentik",
        provider_tenant: @issuer,
        account_linking_policy: :verified_email_existing_principal
      )

    {:ok, issued} =
      Identity.issue_human_session(
        linked.principal,
        linked.external_identity_link,
        %{
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id
        },
        authentication_method: "oidc",
        source_surface: "web",
        trace_id: "#{prefix}-trace"
      )

    issued
  end

  defp bootstrap(prefix) do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_slug: unique("#{prefix}-org"),
        workspace_slug: unique("#{prefix}-workspace"),
        initiative_slug: unique("#{prefix}-initiative"),
        owner_email: "#{unique("#{prefix}-owner")}@example.test"
      )

    bootstrap
  end

  defp claims(email, subject) do
    %{
      "sub" => subject,
      "email" => email,
      "email_verified" => true,
      "name" => "OIDC User"
    }
  end

  defp login_transaction do
    %{
      state: "state",
      nonce: "nonce",
      pkce_verifier: String.duplicate("v", 64),
      redirect_uri: @redirect_uri,
      return_to: "/operator",
      issued_at_unix: System.system_time(:second)
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
