defmodule OfficeGraphWeb.AuthenticationControllerTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.Authentication.OidcClient.TestAdapter
  alias OfficeGraph.{Foundation, Identity}
  alias OfficeGraph.Authorization.{PersistenceTestAdapter, RoleAssignment}
  alias OfficeGraph.Identity.{AuthenticationEvent, Principal}
  alias OfficeGraph.Identity.HumanSessionPersistenceTestAdapter
  alias OfficeGraph.Tenancy.Organization

  require Ash.Query

  @moduletag :unauthenticated

  @issuer "https://authentik.office-graph.local/application/o/office-graph/"
  @redirect_uri "http://localhost:4002/auth/callback"

  setup do
    original_config = Application.get_env(:office_graph, :human_oidc)
    original_client = Application.get_env(:office_graph, :human_oidc_client)

    original_local_development =
      Application.get_env(:office_graph, :local_development_authentication)

    Application.put_env(:office_graph, :human_oidc_client, TestAdapter)
    Application.put_env(:office_graph, :local_development_authentication, enabled: false)

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
      restore_env(:local_development_authentication, original_local_development)
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

  test "login rejects return targets that decode to invalid UTF-8" do
    conn = get(build_conn(), "/auth/login", %{"return_to" => "/%FF"})

    assert get_session(conn, :oidc_login_transaction).return_to == "/operator"
  end

  test "login preserves a local return target containing an encoded literal percent" do
    return_to = "/operator?q=100%25free"
    conn = get(build_conn(), "/auth/login", %{"return_to" => return_to})

    assert get_session(conn, :oidc_login_transaction).return_to == return_to
  end

  test "login preserves a once-decoded local return target containing a literal percent" do
    conn = get(build_conn(), "/auth/login?return_to=%2Foperator%3Fq%3D100%25free")

    assert get_session(conn, :oidc_login_transaction).return_to == "/operator?q=100%free"
  end

  test "login rejects a double-encoded return target before callback redirect", %{
    conn: conn
  } do
    bootstrap = bootstrap("double-encoded-return")
    login_conn = get(conn, "/auth/login?return_to=%252Foperator")
    transaction = get_session(login_conn, :oidc_login_transaction)

    assert transaction.return_to == "/operator"

    TestAdapter.put(%{
      exchange: {:ok, claims(bootstrap.principal.email, "double-encoded-return-subject")}
    })

    callback_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{oidc_login_transaction: transaction})
      |> get("/auth/callback", %{
        "code" => "authorization-code",
        "state" => transaction.state
      })

    assert redirected_to(callback_conn) == "/operator"
    assert is_binary(get_session(callback_conn, :human_session_id))
  end

  test "login fails closed when the provider is unavailable", %{conn: conn} do
    Application.put_env(:office_graph, :human_oidc, issuer: @issuer)

    conn = get(conn, ~p"/auth/login")

    assert response(conn, 503) == "Authentication unavailable"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    refute get_session(conn, :oidc_login_transaction)
    assert [request_id] = get_resp_header(conn, "x-request-id")

    assert [event] = Ash.read!(AuthenticationEvent, authorize?: false)
    assert event.event == "login"
    assert event.result == "rejected"
    assert event.reason == "authentication_unavailable"
    assert event.authentication_method == "oidc"
    assert event.source_surface == "web"
    assert event.trace_id == request_id
  end

  test "enabled loopback development login renders fixed choices and preserves a safe return target",
       %{conn: conn} do
    enable_local_development_authentication()
    _seeded = local_development_seed("chooser")

    conn = get(conn, ~p"/auth/login?return_to=/runs")
    body = html_response(conn, 200)

    assert body =~ "Local development sign in"
    assert body =~ ~s(value="owner")
    assert body =~ ~s(value="workspace_admin")
    assert body =~ ~s(value="member")
    assert body =~ ~s(value="deprovisioned_member")
    assert body =~ ~s(href="/auth/login?provider=oidc")
    refute body =~ ~s(name="return_to")
    assert get_session(conn, :authentication_return_to) == "/runs"
  end

  test "development login uses CSRF and issues a fixed fixture session", %{conn: conn} do
    enable_local_development_authentication()
    seeded = local_development_seed("fixture-login")

    chooser_conn = get(conn, ~p"/auth/login?return_to=/packets")
    csrf_token = csrf_token!(html_response(chooser_conn, 200))

    login_conn =
      chooser_conn
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/development/login", %{
        "_csrf_token" => csrf_token,
        "fixture" => "member"
      })

    assert redirected_to(login_conn) == "/packets"
    assert %{"human_session_id" => session_id} = get_session(login_conn)

    assert {:ok, session} =
             OfficeGraph.Authentication.resolve_session(session_id,
               trace_id: "fixture-login-resolve",
               source_surface: "test"
             )

    assert session.principal_id == seeded.fixtures["member"].identity.principal.id
    assert session.authentication_method == "local_development"
  end

  test "development login rejects missing CSRF evidence", %{conn: conn} do
    enable_local_development_authentication()
    _seeded = local_development_seed("csrf")

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> enforce_csrf()
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/development/login", %{"fixture" => "owner"})
    end
  end

  test "development login does not seed missing fixtures from the request", %{conn: conn} do
    enable_local_development_authentication()
    assert Ash.count!(Organization, authorize?: false) == 0

    chooser_conn = get(conn, ~p"/auth/login")
    csrf_token = csrf_token!(html_response(chooser_conn, 200))

    login_conn =
      chooser_conn
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/development/login", %{
        "_csrf_token" => csrf_token,
        "fixture" => "owner"
      })

    assert html_response(login_conn, 503) =~ "mix demo.seed"
    assert Ash.count!(Organization, authorize?: false) == 0
  end

  test "development routes require explicit enablement and an exact loopback peer", %{conn: conn} do
    disabled_conn =
      conn
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/development/login", %{})

    assert response(disabled_conn, 404) == "Not found"
    assert get_resp_header(disabled_conn, "content-type") == ["text/plain; charset=utf-8"]

    enable_local_development_authentication()

    remote_conn =
      build_conn()
      |> Map.put(:remote_ip, {192, 0, 2, 10})
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/development/login", %{})

    assert response(remote_conn, 404) == "Not found"

    oidc_conn =
      build_conn()
      |> Map.put(:remote_ip, {192, 0, 2, 10})
      |> get(~p"/auth/login")

    assert redirected_to(oidc_conn) == "https://authentik.office-graph.local/authorize"
  end

  test "explicit OIDC selection remains available from the development chooser", %{conn: conn} do
    enable_local_development_authentication()

    conn = get(conn, ~p"/auth/login?provider=oidc&return_to=/runs")

    assert redirected_to(conn) == "https://authentik.office-graph.local/authorize"
    assert get_session(conn, :oidc_login_transaction).return_to == "/runs"
  end

  test "callback clears a mismatched-state cookie without calling the provider", %{conn: conn} do
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

    transaction = login_transaction()

    conn =
      conn
      |> Plug.Test.init_test_session(%{oidc_login_transaction: transaction})
      |> get("/auth/callback", %{
        "code" => "authorization-code",
        "state" => transaction.state
      })

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
      |> get("/auth/callback", %{
        "code" => "authorization-code",
        "state" => transaction.state
      })

    assert redirected_to(conn) == "/operator"
    assert is_binary(get_session(conn, :human_session_id))
  end

  test "callback provider failure leaves no authenticated session", %{conn: conn} do
    TestAdapter.put(%{exchange: {:error, :provider_down}})

    transaction = login_transaction()

    conn =
      conn
      |> Plug.Test.init_test_session(%{oidc_login_transaction: transaction})
      |> get("/auth/callback", %{
        "code" => "authorization-code",
        "state" => transaction.state
      })

    assert response(conn, 401) == "Authentication failed"
    refute get_session(conn, :oidc_login_transaction)
    refute get_session(conn, :human_session_id)
  end

  test "callback reports rejected-login evidence storage failures as unavailable", %{conn: conn} do
    principal =
      Ash.create!(
        Principal,
        %{
          id: Ecto.UUID.generate(),
          email: "#{unique("callback-evidence-storage")}@example.test",
          kind: "human",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    login_conn = get(conn, ~p"/auth/login")
    transaction = get_session(login_conn, :oidc_login_transaction)

    TestAdapter.put(%{
      exchange: {:ok, claims(principal.email, "callback-evidence-storage-subject")}
    })

    HumanSessionPersistenceTestAdapter.configure!(event: {:error, :database_unavailable})

    callback_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{oidc_login_transaction: transaction})
      |> get("/auth/callback", %{
        "code" => "authorization-code",
        "state" => transaction.state
      })

    assert response(callback_conn, 503) == "Authentication unavailable"
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
    HumanSessionPersistenceTestAdapter.configure!(revoke: {:error, :database_unavailable})

    conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/logout")

    assert response(conn, 503) == "Logout unavailable"
    assert get_session(conn, :human_session_id) == issued.session.id
    refute conn.private.plug_session_info == :drop
  end

  test "local development logout revokes and returns directly to the chooser", %{conn: conn} do
    enable_local_development_authentication()
    _seeded = local_development_seed("local-web-logout")

    {:ok, completed} =
      OfficeGraph.Authentication.complete_local_development_login("owner",
        trace_id: "local-web-logout-login",
        source_surface: "web"
      )

    conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: completed.session.id})
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/logout")

    assert redirected_to(conn) == "/auth/login"
    assert conn.private.plug_session_info == :drop
    assert {:error, :invalid_session} = Identity.resolve_human_session(completed.session.id)
  end

  test "identity switching revokes the prior session before issuing the next one", %{conn: conn} do
    enable_local_development_authentication()
    seeded = local_development_seed("local-switch")

    {:ok, owner} =
      OfficeGraph.Authentication.complete_local_development_login("owner",
        trace_id: "local-switch-owner",
        source_surface: "web"
      )

    chooser_conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: owner.session.id})
      |> get(~p"/auth/login?return_to=/runs")

    switch_conn =
      chooser_conn
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/development/switch", %{
        "_csrf_token" => csrf_token!(html_response(chooser_conn, 200)),
        "fixture" => "member"
      })

    assert redirected_to(switch_conn) == "/runs"
    new_session_id = get_session(switch_conn, :human_session_id)
    assert new_session_id != owner.session.id
    assert {:error, :invalid_session} = Identity.resolve_human_session(owner.session.id)
    assert {:ok, member} = Identity.resolve_human_session(new_session_id)
    assert member.principal_id == seeded.fixtures["member"].identity.principal.id
  end

  test "identity switching preserves the current cookie when revocation fails", %{conn: conn} do
    enable_local_development_authentication()
    _seeded = local_development_seed("local-switch-failure")

    {:ok, owner} =
      OfficeGraph.Authentication.complete_local_development_login("owner",
        trace_id: "local-switch-failure-owner",
        source_surface: "web"
      )

    chooser_conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: owner.session.id})
      |> get(~p"/auth/login")

    HumanSessionPersistenceTestAdapter.configure!(revoke: {:error, :database_unavailable})

    switch_conn =
      chooser_conn
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("origin", OfficeGraphWeb.Endpoint.url())
      |> post(~p"/auth/development/switch", %{
        "_csrf_token" => csrf_token!(html_response(chooser_conn, 200)),
        "fixture" => "member"
      })

    assert html_response(switch_conn, 503) =~ "temporarily unavailable"
    assert get_session(switch_conn, :human_session_id) == owner.session.id
    assert {:ok, _current} = Identity.resolve_human_session(owner.session.id)
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
    HumanSessionPersistenceTestAdapter.configure!(resolve: {:error, :database_unavailable})

    conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> get(~p"/operator")

    assert redirected_to(conn) =~ "/auth/login"
    assert get_session(conn, :human_session_id) == issued.session.id
  end

  test "product pages reject sessions whose workspace role assignment was removed", %{conn: conn} do
    issued = issue_session("removed-role-assignment")

    RoleAssignment
    |> Ash.Query.filter(
      principal_id == ^issued.session.principal_id and
        organization_id == ^issued.session.organization_id and
        workspace_id == ^issued.session.workspace_id
    )
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, action: :revoke, authorize?: false))

    conn =
      conn
      |> Plug.Test.init_test_session(%{human_session_id: issued.session.id})
      |> put_req_header("x-request-id", "removed-role-assignment-reuse")
      |> get(~p"/operator")

    assert redirected_to(conn) =~ "/auth/login"
    refute get_session(conn, :human_session_id)

    event =
      AuthenticationEvent
      |> Ash.Query.filter(
        session_id == ^issued.session.id and event == "session_validation" and
          result == "rejected"
      )
      |> Ash.read_one!(authorize?: false)

    assert event.reason == "invalid_scope"
    assert event.trace_id == "removed-role-assignment-reuse"
  end

  test "product pages preserve the cookie across transient authorization storage failures", %{
    conn: conn
  } do
    issued = issue_session("authorization-storage")
    PersistenceTestAdapter.configure!(login_scope: {:error, :database_unavailable})

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

  defp local_development_seed(prefix) do
    {:ok, seeded} =
      Foundation.seed_local_development_fixtures(
        organization_name: "Local Development #{prefix}",
        organization_slug: unique("#{prefix}-org"),
        workspace_name: "Development",
        workspace_slug: unique("#{prefix}-workspace"),
        initiative_name: "Local Authentication",
        initiative_slug: unique("#{prefix}-initiative")
      )

    seeded
  end

  defp enable_local_development_authentication do
    Application.put_env(:office_graph, :local_development_authentication, enabled: true)
  end

  defp csrf_token!(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp enforce_csrf(conn) do
    update_in(conn.private, &Map.delete(&1, :plug_skip_csrf_protection))
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
    issued_at_unix = System.system_time(:second)

    transaction = %{
      id: Ecto.UUID.generate(),
      state: "state",
      nonce: "nonce",
      pkce_verifier: String.duplicate("v", 64),
      redirect_uri: @redirect_uri,
      return_to: "/operator",
      issued_at_unix: issued_at_unix
    }

    :ok = Identity.store_oidc_login_transaction(transaction.id, issued_at_unix + 600)
    transaction
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
