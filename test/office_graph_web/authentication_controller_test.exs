defmodule OfficeGraphWeb.AuthenticationControllerTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Authentication.OidcClient.TestAdapter
  alias OfficeGraph.{Foundation, Identity}
  alias OfficeGraph.Identity.AuthenticationEvent
  alias OfficeGraph.Tenancy.Organization

  require Ash.Query

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

  test "login rejects encoded backslashes in return targets" do
    for return_to <- [
          "/%5cevil.example",
          "/%5C%5Cattacker.example",
          "/%255C%255Cattacker.example",
          "/\\attacker.example"
        ] do
      conn = get(build_conn(), "/auth/login", %{"return_to" => return_to})

      assert get_session(conn, :oidc_login_transaction).return_to == "/operator"
    end
  end

  test "login rejects decoded URL control characters in return targets" do
    for return_to <- [
          "/%09/attacker.example",
          "/%2509/attacker.example",
          "/%0B/attacker.example",
          "/%1F/attacker.example",
          "/%7F/attacker.example"
        ] do
      conn = get(build_conn(), "/auth/login", %{"return_to" => return_to})

      assert get_session(conn, :oidc_login_transaction).return_to == "/operator"
    end
  end

  test "login preserves a local return target containing an encoded literal percent" do
    return_to = "/operator?q=100%25free"
    conn = get(build_conn(), "/auth/login", %{"return_to" => return_to})

    assert get_session(conn, :oidc_login_transaction).return_to == return_to
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
    assert get_session(conn) == %{"human_session_id" => session_id}
    assert {:ok, session_context} = Identity.resolve_human_session(session_id)
    assert session_context.principal_id == bootstrap.principal.id

    set_cookie = conn |> get_resp_header("set-cookie") |> Enum.join(";")
    assert set_cookie =~ "HttpOnly"
    assert set_cookie =~ "SameSite=Lax"
  end

  test "callback defaults a validated legacy transaction without a return target", %{conn: conn} do
    bootstrap = bootstrap("callback-default-return")

    TestAdapter.put(%{
      exchange: {:ok, claims(bootstrap.principal.email, "callback-default-return-subject")}
    })

    transaction = Map.delete(login_transaction(), :return_to)

    conn =
      conn
      |> Plug.Test.init_test_session(%{oidc_login_transaction: transaction})
      |> get(~p"/auth/callback?code=authorization-code&state=state")

    assert redirected_to(conn) == "/operator"
    assert is_binary(get_session(conn, :human_session_id))
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
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/logout")

    assert redirected_to(conn) == "/auth/logged-out"
    assert conn.private.plug_session_info == :drop
    assert {:error, :invalid_session} = Identity.resolve_human_session(issued.session.id)

    assert TestAdapter.request(:logout_uri).post_logout_redirect_uri ==
             "#{OfficeGraphWeb.Endpoint.url()}/auth/logged-out"

    logged_out_conn = get(build_conn(), ~p"/auth/logged-out")

    assert html_response(logged_out_conn, 200) =~ ~s(href="/auth/login")
    assert TestAdapter.calls(:authorization_uri) == 0
  end

  test "logout preserves the session cookie when durable revocation is unavailable", %{conn: conn} do
    issued = issue_session("logout-storage")
    OfficeGraph.Repo.query!("ALTER TABLE sessions RENAME TO unavailable_sessions")

    conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/logout")

    assert response(conn, 503) == "Logout unavailable"
    assert get_session(conn, :human_session_id) == issued.session.id
    refute conn.private.plug_session_info == :drop
  end

  test "product pages redirect anonymous requests to login", %{conn: conn} do
    conn = get(conn, ~p"/operator")

    assert conn.status == 302

    assert get_resp_header(conn, "content-security-policy") == [
             "base-uri 'self'; frame-ancestors 'self';"
           ]

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

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
      |> put_req_header("x-request-id", "revoked-product-reuse")
      |> get(~p"/operator")

    assert conn.status == 302
    refute get_session(conn, :human_session_id)

    event =
      AuthenticationEvent
      |> Ash.Query.filter(
        session_id == ^issued.session.id and event == "session_validation" and
          result == "rejected"
      )
      |> Ash.read_one!(authorize?: false)

    assert event.reason == "session_revoked"
    assert event.trace_id == "revoked-product-reuse"
    assert event.source_surface == "web"
  end

  test "product pages preserve the cookie across transient session storage failures", %{
    conn: conn
  } do
    issued = issue_session("unavailable-product")
    OfficeGraph.Repo.query!("ALTER TABLE sessions RENAME TO unavailable_sessions")

    conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> get(~p"/operator")

    assert redirected_to(conn) =~ "/auth/login"
    assert get_session(conn, :human_session_id) == issued.session.id
  end

  test "cookie-authenticated APIs reject cross-origin unsafe requests" do
    issued = issue_session("cross-origin")

    requests = [
      {"/graphql", %{query: "{ __typename }"}},
      {"/api/v1/commands/submit-manual-intake", %{}},
      {"/auth/logout", %{}}
    ]

    for {path, params} <- requests do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
        |> put_req_header("origin", "https://attacker.example")
        |> post(path, params)

      assert response(conn, 403) == "Cross-origin request forbidden"
    end
  end

  test "cookie-authenticated unsafe requests require same-origin evidence" do
    issued = issue_session("missing-origin-evidence")

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> post("/graphql", %{query: "{ __typename }"})

    assert response(conn, 403) == "Cross-origin request forbidden"
  end

  test "cookie-authenticated APIs accept requests from the configured origin" do
    issued = issue_session("same-origin")

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post("/graphql", %{query: "{ __typename }"})

    assert json_response(conn, 200) == %{"data" => %{"__typename" => "RootQueryType"}}
  end

  test "cookie-authenticated GraphQL GET rejects mutations before execution" do
    issued = issue_session("graphql-get")

    query_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> put_req_header("sec-fetch-site", "cross-site")
      |> get("/graphql", %{query: "{ __typename }"})

    assert json_response(query_conn, 200) == %{"data" => %{"__typename" => "RootQueryType"}}

    mutation_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> put_req_header("sec-fetch-site", "cross-site")
      |> get("/graphql", %{query: "mutation { __typename }"})

    assert json_response(mutation_conn, 405) == %{
             "errors" => [%{"message" => "Can only perform a mutation from a POST request"}]
           }
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
