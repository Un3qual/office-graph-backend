defmodule OfficeGraph.EnterpriseIdentity.WorkOSAuthenticationTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.{
    Authentication,
    Authorization,
    EnterpriseIdentity,
    Foundation,
    Identity,
    Operations
  }

  alias OfficeGraph.EnterpriseIdentity.{
    Directory,
    DirectoryGroup,
    EnterpriseConnection,
    ExternalGroupRoleMapping
  }

  alias OfficeGraph.Authorization.Role
  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.DirectoryEvent
  alias OfficeGraph.Identity.Session

  require Ash.Query

  @moduletag :unauthenticated

  @redirect_uri "https://office-graph.test/auth/workos/callback"

  defmodule SsoClient do
    @behaviour OfficeGraph.EnterpriseIdentity.EnterpriseSsoClient

    @impl true
    def authorization_uri(request) do
      send(self(), {:workos_authorization_request, request})
      Process.get({__MODULE__, :authorization_uri}, {:error, :provider_unavailable})
    end

    @impl true
    def exchange(request) do
      send(self(), {:workos_exchange_request, request})
      Process.get({__MODULE__, :exchange}, {:error, :provider_unavailable})
    end
  end

  defmodule OidcLogoutProbe do
    @behaviour OfficeGraph.Authentication.OidcClient

    @impl true
    def authorization_uri(_request), do: {:error, :unsupported}

    @impl true
    def exchange(_request), do: {:error, :unsupported}

    @impl true
    def logout_uri(request) do
      send(self(), {:oidc_logout_uri, request})
      {:ok, "https://authentik.test/logout"}
    end
  end

  setup do
    original_config = Application.get_env(:office_graph, :workos_enterprise)
    original_client = Application.get_env(:office_graph, :workos_sso_client)
    original_human_oidc = Application.get_env(:office_graph, :human_oidc)
    original_human_oidc_client = Application.get_env(:office_graph, :human_oidc_client)

    Application.put_env(:office_graph, :workos_enterprise,
      api_base_url: "https://api.workos.test",
      api_key_reference: "test-secret://workos/api-key",
      client_id: "client_01",
      session_ttl_seconds: 3_600
    )

    Application.put_env(:office_graph, :workos_sso_client, SsoClient)

    Application.put_env(:office_graph, :human_oidc,
      issuer: "https://authentik.test/application/o/office-graph/",
      client_id: "office-graph",
      client_secret: "secret",
      account_linking_policy: :verified_email_existing_principal
    )

    Application.put_env(:office_graph, :human_oidc_client, OidcLogoutProbe)

    Process.put(
      {SsoClient, :authorization_uri},
      {:ok, "https://api.workos.test/sso/authorize"}
    )

    on_exit(fn ->
      restore_env(:workos_enterprise, original_config)
      restore_env(:workos_sso_client, original_client)
      restore_env(:human_oidc, original_human_oidc)
      restore_env(:human_oidc_client, original_human_oidc_client)
    end)

    :ok
  end

  test "connection-bound WorkOS login issues an Office Graph session" do
    context = enterprise_context("success", "required")
    provision_directory_user(context, context.bootstrap.principal.email)

    assert {:ok, login} =
             Authentication.begin_workos_login(
               context.connection.id,
               @redirect_uri,
               return_to: "/runs",
               trace_id: "workos-login-start"
             )

    assert login.authorization_uri == "https://api.workos.test/sso/authorize"

    assert %{
             provider: :workos,
             enterprise_connection_id: connection_id,
             return_to: "/runs"
           } = login.transaction

    assert connection_id == context.connection.id

    assert_received {:workos_authorization_request, request}
    assert request.config.provider_organization_id == context.connection.provider_organization_id
    assert request.redirect_uri == @redirect_uri
    assert request.state == login.transaction.state

    Process.put(
      {SsoClient, :exchange},
      {:ok,
       %{
         subject: "connection_01:idp_user_01",
         idp_id: "idp_user_01",
         verified_email: context.bootstrap.principal.email,
         first_name: "Ada",
         last_name: "Lovelace",
         provider_organization_id: context.connection.provider_organization_id,
         provider_connection_id: "connection_01"
       }}
    )

    assert {:ok, completed} =
             Authentication.complete_workos_login(
               "authorization-code",
               login.transaction.state,
               login.transaction,
               trace_id: "workos-login-complete",
               source_surface: "web"
             )

    assert completed.principal.id == context.bootstrap.principal.id
    assert completed.external_identity_link.provider == "workos_sso"

    assert completed.external_identity_link.provider_tenant ==
             context.connection.provider_organization_id

    session = Ash.get!(Session, completed.session.id, authorize?: false)
    assert session.principal_id == context.bootstrap.principal.id
    assert session.enterprise_connection_id == context.connection.id

    assert_received {:workos_exchange_request, exchange_request}
    assert exchange_request.code == "authorization-code"
    assert exchange_request.redirect_uri == @redirect_uri

    assert {:error, :invalid_login_transaction} =
             Authentication.complete_workos_login(
               "authorization-code",
               login.transaction.state,
               login.transaction,
               []
             )
  end

  test "organization-wide mapped identity completes login into the connection workspace" do
    context = enterprise_context("organization-mapping", "required")
    email = "#{unique("organization-mapped-user")}@example.test"
    idp_id = "idp_organization_mapping"

    user = provision_organization_mapped_user(context, email, idp_id)

    assert {:ok,
            %{
              organization_id: organization_id,
              workspace_id: nil
            }} = Authorization.resolve_login_scope(user.principal_id)

    assert organization_id == context.bootstrap.organization.id

    Process.put(
      {SsoClient, :exchange},
      {:ok,
       %{
         subject: "connection_01:#{idp_id}",
         idp_id: idp_id,
         verified_email: email,
         first_name: "Grace",
         last_name: "Hopper",
         provider_organization_id: context.connection.provider_organization_id,
         provider_connection_id: "connection_01"
       }}
    )

    assert {:ok, login} =
             Authentication.begin_workos_login(
               context.connection.id,
               @redirect_uri,
               trace_id: "organization-mapping-login-start"
             )

    assert {:ok, completed} =
             Authentication.complete_workos_login(
               "authorization-code",
               login.transaction.state,
               login.transaction,
               trace_id: "organization-mapping-login-complete",
               source_surface: "web"
             )

    assert completed.principal.id == user.principal_id
    assert completed.session.organization_id == context.bootstrap.organization.id
    assert completed.session.workspace_id == context.bootstrap.workspace.id

    assert {:ok, session_context} = Authentication.resolve_session(completed.session.id)
    assert session_context.workspace_id == context.bootstrap.workspace.id
  end

  test "browser routes preserve the connection-bound transaction through callback", %{conn: conn} do
    context = enterprise_context("browser", "required")
    provision_directory_user(context, context.bootstrap.principal.email)

    login_conn =
      get(
        conn,
        "/auth/workos/#{context.connection.id}/login",
        %{"return_to" => "/runs"}
      )

    assert redirected_to(login_conn) == "https://api.workos.test/sso/authorize"

    transaction = get_session(login_conn, :oidc_login_transaction)
    assert transaction.enterprise_connection_id == context.connection.id
    assert transaction.provider == :workos

    Process.put(
      {SsoClient, :exchange},
      {:ok,
       %{
         subject: "connection_01:idp_user_01",
         idp_id: "idp_user_01",
         verified_email: context.bootstrap.principal.email,
         first_name: "Ada",
         last_name: "Lovelace",
         provider_organization_id: context.connection.provider_organization_id,
         provider_connection_id: "connection_01"
       }}
    )

    callback_conn =
      build_conn()
      |> Plug.Test.init_test_session(%{oidc_login_transaction: transaction})
      |> get("/auth/workos/callback", %{
        "code" => "authorization-code",
        "state" => transaction.state
      })

    assert redirected_to(callback_conn) == "/runs"
    assert is_binary(get_session(callback_conn, :human_session_id))
    refute get_session(callback_conn, :oidc_login_transaction)
  end

  test "required directory provisioning refuses an otherwise valid SSO identity" do
    context = enterprise_context("provisioning-required", "required")

    Process.put(
      {SsoClient, :exchange},
      {:ok,
       %{
         subject: "connection_01:idp_user_missing",
         idp_id: "idp_user_missing",
         verified_email: context.bootstrap.principal.email,
         first_name: nil,
         last_name: nil,
         provider_organization_id: context.connection.provider_organization_id,
         provider_connection_id: "connection_01"
       }}
    )

    {:ok, login} =
      Authentication.begin_workos_login(context.connection.id, @redirect_uri, [])

    assert {:error, :directory_provisioning_required} =
             Authentication.complete_workos_login(
               "authorization-code",
               login.transaction.state,
               login.transaction,
               []
             )

    refute Session
           |> Ash.Query.filter(
             principal_id == ^context.bootstrap.principal.id and purpose == "human_web"
           )
           |> Ash.exists?(authorize?: false)
  end

  test "optional provisioning preserves verified-email linking policy" do
    context = enterprise_context("optional", "optional")

    Process.put(
      {SsoClient, :exchange},
      {:ok,
       %{
         subject: "connection_01:idp_optional",
         idp_id: "idp_optional",
         verified_email: context.bootstrap.principal.email,
         first_name: nil,
         last_name: nil,
         provider_organization_id: context.connection.provider_organization_id,
         provider_connection_id: "connection_01"
       }}
    )

    {:ok, login} =
      Authentication.begin_workos_login(context.connection.id, @redirect_uri, [])

    assert {:ok, completed} =
             Authentication.complete_workos_login(
               "authorization-code",
               login.transaction.state,
               login.transaction,
               []
             )

    assert completed.principal.id == context.bootstrap.principal.id

    assert {:ok, %{status: :applied, resource: directory_user}} =
             provision_directory_user(
               context,
               context.bootstrap.principal.email,
               "idp_optional"
             )

    assert directory_user.principal_id == completed.principal.id
    assert directory_user.principal_origin == "reused"
  end

  test "disabled connections and cross-provider transactions fail closed" do
    context = enterprise_context("disabled", "required")

    context.connection
    |> Ash.Changeset.for_update(:set_lifecycle, %{status: "disabled"})
    |> Ash.update!(authorize?: false)

    assert {:error, :enterprise_connection_unavailable} =
             Authentication.begin_workos_login(context.connection.id, @redirect_uri, [])

    assert {:error, :invalid_login_transaction} =
             Authentication.complete_workos_login(
               "authorization-code",
               "state",
               %{
                 id: Ecto.UUID.generate(),
                 provider: :oidc,
                 enterprise_connection_id: context.connection.id,
                 state: "state",
                 redirect_uri: @redirect_uri,
                 issued_at_unix: System.system_time(:second)
               },
               []
             )
  end

  test "disabling the issuing connection revokes its WorkOS session permanently" do
    context = enterprise_context("session-connection-lifecycle", "required")
    provision_directory_user(context, context.bootstrap.principal.email)
    completed = complete_workos_login!(context, "idp_user_01")

    {:ok, operation} =
      Operations.start_operation(context.bootstrap.session, :enterprise_identity_manage)

    assert {:ok, disabled_connection} =
             EnterpriseIdentity.set_connection_lifecycle(
               context.bootstrap.session,
               operation,
               context.connection.id,
               %{status: "disabled"}
             )

    assert disabled_connection.status == "disabled"

    assert {:error, :invalid_session} =
             Authentication.resolve_session(completed.session.id,
               trace_id: "disabled-workos-session"
             )

    assert %DateTime{} =
             Ash.get!(Session, completed.session.id, authorize?: false).revoked_at

    assert {:ok, enabled_connection} =
             EnterpriseIdentity.set_connection_lifecycle(
               context.bootstrap.session,
               operation,
               context.connection.id,
               %{status: "active"}
             )

    assert enabled_connection.status == "active"

    assert {:error, :invalid_session} =
             Authentication.resolve_session(completed.session.id,
               trace_id: "re-enabled-workos-session"
             )
  end

  test "WorkOS logout revokes locally without contacting the generic OIDC provider" do
    context = enterprise_context("provider-aware-logout", "required")
    provision_directory_user(context, context.bootstrap.principal.email)
    completed = complete_workos_login!(context, "idp_user_01")

    assert {:ok, %{provider_logout_uri: nil}} =
             Authentication.logout(completed.session.id,
               trace_id: "workos-logout",
               post_logout_redirect_uri: "https://office-graph.test/"
             )

    refute_received {:oidc_logout_uri, _request}
    assert {:error, :invalid_session} = Authentication.resolve_session(completed.session.id)
  end

  defp enterprise_context(label, directory_requirement) do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_slug: unique("#{label}-organization"),
        workspace_slug: unique("#{label}-workspace"),
        initiative_slug: unique("#{label}-initiative"),
        owner_email: "#{unique(label)}@example.test"
      )

    {:ok, webhook_principal} =
      Identity.ensure_system_principal(
        "#{unique("#{label}-webhook")}@office-graph.local",
        "webhook"
      )

    assert :ok =
             Authorization.ensure_system_role(
               webhook_principal,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id
               },
               [:provider_webhook_receive]
             )

    {:ok, request} =
      Operations.new_system_operation_request(%{
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        principal_id: webhook_principal.id,
        action: :provider_webhook_receive,
        authority_basis: "workos:test:#{label}",
        causation_key: "workos:test:#{label}",
        idempotency_scope: "workos:test",
        idempotency_key: label
      })

    {:ok, operation} = Operations.start_system_operation(request)

    connection =
      Ash.create!(
        EnterpriseConnection,
        %{
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          webhook_principal_id: webhook_principal.id,
          operation_id: operation.id,
          provider: "workos",
          provider_organization_id: unique("workos-organization"),
          directory_requirement: directory_requirement,
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    directory =
      Ash.create!(
        Directory,
        %{
          connection_id: connection.id,
          operation_id: operation.id,
          provider_directory_id: unique("workos-directory"),
          status: "active",
          provider_updated_at: ~U[2026-07-29 19:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    %{
      bootstrap: bootstrap,
      connection: connection,
      directory: directory,
      operation: operation
    }
  end

  defp provision_directory_user(context, email, idp_id \\ "idp_user_01") do
    event =
      DirectoryEvent.new!(
        provider_event_id: unique("event"),
        event_type: "dsync.user.created",
        directory_id: context.directory.provider_directory_id,
        resource_kind: :user,
        action: :upsert,
        provider_occurred_at: ~U[2026-07-29 20:00:00Z],
        data: %{
          provider_user_id: "directory_user_01",
          idp_id: idp_id,
          email: email,
          first_name: "Ada",
          last_name: "Lovelace",
          status: "active",
          provider_updated_at: ~U[2026-07-29 20:00:00Z]
        }
      )

    EnterpriseIdentity.apply_directory_event(
      context.directory.id,
      event,
      context.operation.id
    )
  end

  defp provision_organization_mapped_user(context, email, idp_id) do
    event_time = ~U[2026-07-30 20:00:00Z]

    assert {:ok, %{status: :applied, resource: user}} =
             provision_directory_user(context, email, idp_id)

    group_event =
      DirectoryEvent.new!(
        provider_event_id: unique("group-event"),
        event_type: "dsync.group.created",
        directory_id: context.directory.provider_directory_id,
        resource_kind: :group,
        action: :upsert,
        provider_occurred_at: event_time,
        data: %{
          provider_group_id: "directory_group_organization",
          name: "Organization Engineering",
          status: "active",
          provider_updated_at: event_time
        }
      )

    assert {:ok, %{status: :applied, resource: %DirectoryGroup{} = group}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               group_event,
               context.operation.id
             )

    membership_event =
      DirectoryEvent.new!(
        provider_event_id: unique("membership-event"),
        event_type: "dsync.group.user_added",
        directory_id: context.directory.provider_directory_id,
        resource_kind: :membership,
        action: :add,
        provider_occurred_at: event_time,
        data: %{
          provider_group_id: "directory_group_organization",
          provider_user_id: "directory_user_01",
          status: "active",
          provider_updated_at: event_time
        }
      )

    assert {:ok, %{status: :applied}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               membership_event,
               context.operation.id
             )

    role =
      Role
      |> Ash.Query.filter(
        organization_id == ^context.bootstrap.organization.id and key == "owner"
      )
      |> Ash.read_one!(authorize?: false)

    Ash.create!(
      ExternalGroupRoleMapping,
      %{
        directory_group_id: group.id,
        role_id: role.id,
        organization_id: context.bootstrap.organization.id,
        workspace_id: nil,
        operation_id: context.operation.id,
        status: "active"
      },
      action: :create,
      authorize?: false
    )

    user
  end

  defp complete_workos_login!(context, idp_id) do
    Process.put(
      {SsoClient, :exchange},
      {:ok,
       %{
         subject: "connection_01:#{idp_id}",
         idp_id: idp_id,
         verified_email: context.bootstrap.principal.email,
         first_name: "Ada",
         last_name: "Lovelace",
         provider_organization_id: context.connection.provider_organization_id,
         provider_connection_id: "connection_01"
       }}
    )

    assert {:ok, login} =
             Authentication.begin_workos_login(
               context.connection.id,
               @redirect_uri,
               trace_id: unique("workos-login-start")
             )

    assert {:ok, completed} =
             Authentication.complete_workos_login(
               "authorization-code",
               login.transaction.state,
               login.transaction,
               trace_id: unique("workos-login-complete"),
               source_surface: "web"
             )

    completed
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
