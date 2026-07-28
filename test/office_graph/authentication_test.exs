defmodule OfficeGraph.AuthenticationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Authentication
  alias OfficeGraph.Authentication.OidcClient.TestAdapter
  alias OfficeGraph.Authentication.OidcClient.Oidcc
  alias OfficeGraph.Authorization
  alias OfficeGraph.Authorization.{Role, RoleAssignment}
  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity
  alias OfficeGraph.Identity.{AuthenticationEvent, ExternalIdentityLink, Principal}
  alias OfficeGraph.Repo

  require Ash.Query

  @issuer "https://authentik.office-graph.local/application/o/office-graph/"
  @redirect_uri "http://localhost:4000/auth/callback"

  setup do
    original_config = Application.get_env(:office_graph, :human_oidc)
    original_client = Application.get_env(:office_graph, :human_oidc_client)

    Application.put_env(:office_graph, :human_oidc_client, TestAdapter)
    Application.put_env(:office_graph, :human_oidc, oidc_config())

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

  describe "begin_login/2" do
    test "creates distinct state, nonce, and PKCE transactions for the adapter" do
      assert {:ok, first} =
               Authentication.begin_login(@redirect_uri,
                 return_to: "/operator"
               )

      assert {:ok, second} =
               Authentication.begin_login(@redirect_uri,
                 return_to: "/runs"
               )

      assert first.authorization_uri == "https://authentik.office-graph.local/authorize"
      assert first.transaction.state != second.transaction.state
      assert first.transaction.nonce != second.transaction.nonce
      assert first.transaction.pkce_verifier != second.transaction.pkce_verifier
      assert byte_size(first.transaction.state) >= 32
      assert byte_size(first.transaction.nonce) >= 32
      assert byte_size(first.transaction.pkce_verifier) >= 43
      assert first.transaction.redirect_uri == @redirect_uri
      assert first.transaction.return_to == "/operator"
      assert is_integer(first.transaction.issued_at_unix)

      request = TestAdapter.request(:authorization_uri)
      assert request.config.issuer == @issuer
      assert request.redirect_uri == @redirect_uri
      assert request.state == second.transaction.state
      assert request.nonce == second.transaction.nonce
      assert request.pkce_verifier == second.transaction.pkce_verifier
    end

    test "prunes expired transaction guards while retaining live guards" do
      now = System.system_time(:second)
      expired_id = Ecto.UUID.generate()
      live_id = Ecto.UUID.generate()

      :ok = Identity.store_oidc_login_transaction(live_id, now + 600)

      Repo.query!(
        """
        INSERT INTO oidc_login_transactions (id, expires_at, inserted_at)
        VALUES ($1, $2, CURRENT_TIMESTAMP)
        """,
        [
          Ecto.UUID.dump!(expired_id),
          DateTime.from_unix!(now - 1)
        ]
      )

      assert {:ok, %{transaction: transaction}} =
               Authentication.begin_login(@redirect_uri, return_to: "/operator")

      assert %{rows: [[false, true, true]]} =
               Repo.query!(
                 """
                 SELECT
                   EXISTS(SELECT 1 FROM oidc_login_transactions WHERE id = $1),
                   EXISTS(SELECT 1 FROM oidc_login_transactions WHERE id = $2),
                   EXISTS(SELECT 1 FROM oidc_login_transactions WHERE id = $3)
                 """,
                 [
                   Ecto.UUID.dump!(expired_id),
                   Ecto.UUID.dump!(live_id),
                   Ecto.UUID.dump!(transaction.id)
                 ]
               )
    end

    test "fails closed when OIDC configuration is missing or partial" do
      Application.put_env(:office_graph, :human_oidc, issuer: @issuer)

      assert {:error, :authentication_unavailable} =
               Authentication.begin_login(@redirect_uri, [])

      assert TestAdapter.calls(:authorization_uri) == 0
    end

    test "reports rejected login-start evidence storage failures" do
      TestAdapter.put(%{authorization_uri: {:error, :provider_down}})
      Repo.query!("ALTER TABLE authentication_events RENAME TO unavailable_authentication_events")

      assert {:error, :identity_storage_unavailable} =
               Authentication.begin_login(@redirect_uri,
                 trace_id: "login-start-evidence-storage",
                 source_surface: "web"
               )
    end
  end

  describe "OIDC adapter failures" do
    test "does not disguise an invalid internal request as provider downtime" do
      # Keep this fixture runtime-dynamic so Elixir does not reject the deliberately
      # incomplete map before the adapter boundary can exercise it.
      invalid_config = Process.get({__MODULE__, :missing_oidc_config}, %{})

      assert_raise KeyError, fn ->
        Oidcc.authorization_uri(%{
          config: invalid_config,
          redirect_uri: @redirect_uri,
          state: "state",
          nonce: "nonce",
          pkce_verifier: String.duplicate("v", 64)
        })
      end
    end
  end

  describe "complete_login/4" do
    test "validates callback state inside the authentication boundary" do
      assert {:error, :invalid_login_transaction} =
               Authentication.complete_login(
                 "authorization-code",
                 "wrong-state",
                 login_transaction(),
                 trace_id: "mismatched-state",
                 source_surface: "web"
               )

      assert TestAdapter.calls(:exchange) == 0
    end

    test "consumes the login transaction when callback state is invalid" do
      transaction = login_transaction()

      assert {:error, :invalid_login_transaction} =
               Authentication.complete_login(
                 "authorization-code",
                 "wrong-state",
                 transaction,
                 trace_id: "mismatched-state-first-attempt",
                 source_surface: "web"
               )

      assert {:error, :invalid_login_transaction} =
               Authentication.complete_login(
                 "authorization-code",
                 transaction.state,
                 transaction,
                 trace_id: "mismatched-state-replay",
                 source_surface: "web"
               )

      assert TestAdapter.calls(:exchange) == 0
    end

    test "records a rejected login when the callback transaction is missing" do
      assert {:error, :invalid_login_transaction} =
               Authentication.complete_login(
                 "authorization-code",
                 "state",
                 nil,
                 trace_id: "missing-login-transaction",
                 source_surface: "web"
               )

      event =
        AuthenticationEvent
        |> Ash.Query.filter(trace_id == "missing-login-transaction")
        |> Ash.read_one!(authorize?: false)

      assert event.event == "login"
      assert event.result == "rejected"
      assert event.reason == "invalid_login_transaction"
      assert event.principal_id == nil
      assert event.external_identity_link_id == nil
      assert TestAdapter.calls(:exchange) == 0
    end

    test "reconciles validated claims, selects the one internal scope, and issues a session" do
      bootstrap = bootstrap("complete-login")

      TestAdapter.put(%{
        exchange: {:ok, claims(bootstrap.principal.email, "complete-subject")}
      })

      transaction = login_transaction()

      assert {:ok, completed} =
               Authentication.complete_login("authorization-code", transaction.state, transaction,
                 trace_id: "complete-login-trace",
                 source_surface: "web"
               )

      assert completed.principal.id == bootstrap.principal.id
      assert completed.external_identity_link.subject == "complete-subject"
      assert completed.session_context.organization_id == bootstrap.organization.id
      assert completed.session_context.workspace_id == bootstrap.workspace.id
      assert completed.session.authentication_method == "oidc"

      request = TestAdapter.request(:exchange)
      assert request.code == "authorization-code"
      assert request.redirect_uri == @redirect_uri
      assert request.nonce == transaction.nonce
      assert request.pkce_verifier == transaction.pkce_verifier
    end

    test "atomically permits only one callback exchange for a login transaction" do
      bootstrap = bootstrap("single-use-callback")

      assert {:ok, %{transaction: transaction}} =
               Authentication.begin_login(@redirect_uri, return_to: "/operator")

      complete = fn ->
        TestAdapter.put(%{
          exchange: {:ok, claims(bootstrap.principal.email, "single-use-callback-subject")}
        })

        Authentication.complete_login(
          "authorization-code",
          transaction.state,
          transaction,
          trace_id: Ecto.UUID.generate(),
          source_surface: "web"
        )
      end

      results =
        [Task.async(complete), Task.async(complete)]
        |> Task.await_many(10_000)

      assert Enum.count(results, &match?({:ok, _completed}, &1)) == 1

      assert Enum.count(
               results,
               &match?({:error, :invalid_login_transaction}, &1)
             ) == 1
    end

    test "rejects an expired login transaction before provider exchange" do
      transaction =
        login_transaction()
        |> Map.put(:issued_at_unix, System.system_time(:second) - 601)

      assert {:error, :invalid_login_transaction} =
               Authentication.complete_login("authorization-code", transaction.state, transaction,
                 trace_id: "expired-transaction",
                 source_surface: "web"
               )

      assert TestAdapter.calls(:exchange) == 0
    end

    test "requires a preferred configured scope when role assignments span workspaces" do
      first = bootstrap("multi-scope-first")

      {:ok, second} =
        Foundation.bootstrap_local_owner(
          organization_name: first.organization.name,
          organization_slug: first.organization.slug,
          workspace_name: "Second Workspace",
          workspace_slug: unique("multi-scope-second-workspace"),
          initiative_name: "Second Initiative",
          initiative_slug: unique("multi-scope-second-initiative"),
          owner_email: first.principal.email,
          owner_name: "Multi Scope Owner"
        )

      TestAdapter.put(%{
        exchange: {:ok, claims(first.principal.email, "multi-scope-subject")}
      })

      transaction = login_transaction()

      assert {:error, :scope_selection_required} =
               Authentication.complete_login(
                 "authorization-code",
                 transaction.state,
                 transaction,
                 trace_id: "multi-scope-no-preference",
                 source_surface: "web"
               )

      Application.put_env(
        :office_graph,
        :human_oidc,
        oidc_config(
          preferred_scope: %{
            organization_id: second.organization.id,
            workspace_id: second.workspace.id
          }
        )
      )

      transaction = login_transaction()

      assert {:ok, completed} =
               Authentication.complete_login(
                 "authorization-code",
                 transaction.state,
                 transaction,
                 trace_id: "multi-scope-preferred",
                 source_surface: "web"
               )

      assert completed.session_context.organization_id == second.organization.id
      assert completed.session_context.workspace_id == second.workspace.id
    end

    test "rejects a reconciled principal with no internal workspace role assignment" do
      principal =
        Ash.create!(
          Principal,
          %{
            id: Ecto.UUID.generate(),
            email: "#{unique("no-scope")}@example.test",
            kind: "human",
            status: "active"
          },
          action: :create,
          authorize?: false
        )

      TestAdapter.put(%{exchange: {:ok, claims(principal.email, "no-scope-subject")}})

      transaction = login_transaction()

      assert {:error, :no_login_scope} =
               Authentication.complete_login(
                 "authorization-code",
                 transaction.state,
                 transaction,
                 trace_id: "no-scope",
                 source_surface: "web"
               )

      event =
        AuthenticationEvent
        |> Ash.Query.filter(trace_id == "no-scope")
        |> Ash.read_one!(authorize?: false)

      link =
        ExternalIdentityLink
        |> Ash.Query.filter(subject == "no-scope-subject")
        |> Ash.read_one!(authorize?: false)

      assert event.principal_id == principal.id
      assert event.external_identity_link_id == link.id
      assert event.session_id == nil
      assert event.organization_id == nil
      assert event.workspace_id == nil
    end

    test "propagates rejected-login evidence storage failures" do
      principal =
        Ash.create!(
          Principal,
          %{
            id: Ecto.UUID.generate(),
            email: "#{unique("rejection-evidence-storage")}@example.test",
            kind: "human",
            status: "active"
          },
          action: :create,
          authorize?: false
        )

      assert {:ok, %{transaction: transaction}} =
               Authentication.begin_login(@redirect_uri, return_to: "/operator")

      TestAdapter.put(%{
        exchange: {:ok, claims(principal.email, "rejection-evidence-storage-subject")}
      })

      Repo.query!("ALTER TABLE authentication_events RENAME TO unavailable_authentication_events")

      assert {:error, :identity_storage_unavailable} =
               Authentication.complete_login(
                 "authorization-code",
                 transaction.state,
                 transaction,
                 trace_id: "rejection-evidence-storage",
                 source_surface: "web"
               )
    end

    test "records the durable review link on a rejected login" do
      subject = "review-required-subject"

      TestAdapter.put(%{
        exchange: {:ok, claims("#{unique("review-required")}@example.test", subject)}
      })

      transaction = login_transaction()

      assert {:error, :identity_review_required} =
               Authentication.complete_login(
                 "authorization-code",
                 transaction.state,
                 transaction,
                 trace_id: "review-required",
                 source_surface: "web"
               )

      link =
        ExternalIdentityLink
        |> Ash.Query.filter(subject == ^subject)
        |> Ash.read_one!(authorize?: false)

      event =
        AuthenticationEvent
        |> Ash.Query.filter(trace_id == "review-required")
        |> Ash.read_one!(authorize?: false)

      assert event.external_identity_link_id == link.id
      assert event.principal_id == nil
    end

    test "normalizes provider failure and records a bounded rejected event" do
      TestAdapter.put(%{exchange: {:error, {:http_error, "secret provider response"}}})

      transaction = login_transaction()

      assert {:error, :provider_unavailable} =
               Authentication.complete_login(
                 "authorization-code",
                 transaction.state,
                 transaction,
                 trace_id: "provider-failure",
                 source_surface: "web"
               )

      event =
        AuthenticationEvent
        |> Ash.Query.filter(trace_id == "provider-failure")
        |> Ash.read_one!(authorize?: false)

      assert event.event == "login"
      assert event.result == "rejected"
      assert event.reason == "provider_unavailable"
      refute inspect(event) =~ "secret provider response"
    end
  end

  describe "logout/2" do
    test "revokes locally and succeeds without a provider logout endpoint" do
      bootstrap = bootstrap("logout")

      {:ok, linked} =
        Identity.reconcile_oidc_identity(
          claims(bootstrap.principal.email, "logout-subject"),
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
          trace_id: "logout-login"
        )

      assert {:ok, %{provider_logout_uri: nil}} =
               Authentication.logout(issued.session.id,
                 trace_id: "logout-trace",
                 post_logout_redirect_uri: "http://localhost:4000/"
               )

      assert {:error, :invalid_session} =
               Identity.resolve_human_session(issued.session.id)

      assert TestAdapter.calls(:logout_uri) == 1
    end
  end

  describe "resolve_login_scope/2" do
    test "rejects a preferred scope that is not currently assigned" do
      bootstrap = bootstrap("invalid-preferred")

      assert {:error, :scope_selection_required} =
               Authorization.resolve_login_scope(bootstrap.principal.id, %{
                 organization_id: Ecto.UUID.generate(),
                 workspace_id: Ecto.UUID.generate()
               })
    end

    test "deduplicates multiple roles in the same workspace" do
      bootstrap = bootstrap("deduplicate-scope")

      second_role =
        Ash.create!(
          Role,
          %{
            id: Ecto.UUID.generate(),
            organization_id: bootstrap.organization.id,
            key: unique("second-role"),
            name: "Second role"
          },
          action: :create,
          authorize?: false
        )

      Ash.create!(
        RoleAssignment,
        %{
          id: Ecto.UUID.generate(),
          principal_id: bootstrap.principal.id,
          role_id: second_role.id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id
        },
        action: :create,
        authorize?: false
      )

      assert {:ok, scope} = Authorization.resolve_login_scope(bootstrap.principal.id)

      assert scope == %{
               organization_id: bootstrap.organization.id,
               workspace_id: bootstrap.workspace.id
             }
    end
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
      "name" => "OIDC User",
      "groups" => ["owner"],
      "roles" => ["system.conformance"]
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

  defp oidc_config(overrides \\ []) do
    [
      issuer: @issuer,
      client_id: "office-graph-test",
      client_secret: "test-client-secret",
      account_linking_policy: :verified_email_existing_principal,
      session_ttl_seconds: 3_600
    ]
    |> Keyword.merge(overrides)
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
