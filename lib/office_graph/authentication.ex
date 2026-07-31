defmodule OfficeGraph.Authentication do
  @moduledoc """
  Public boundary for human OIDC login, session issuance, and logout.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.EnterpriseIdentity,
      OfficeGraph.Identity
    ],
    exports: [LocalDevelopmentFixtures, OidcClient]

  alias OfficeGraph.{Authorization, EnterpriseIdentity, Identity}
  alias OfficeGraph.Authentication.{LocalDevelopment, LocalDevelopmentFixtures}
  alias OfficeGraph.Authentication.OidcClient.Oidcc, as: OidccClient

  @login_transaction_ttl_seconds 10 * 60
  @default_return_to "/operator"
  @default_session_ttl_seconds 8 * 60 * 60
  @transient_storage_errors [
    :identity_storage_unavailable,
    :authorization_storage_unavailable,
    :enterprise_identity_storage_unavailable
  ]

  def begin_login(redirect_uri, opts \\ [])

  def begin_login(redirect_uri, opts) when is_binary(redirect_uri) and is_list(opts) do
    result =
      with {:ok, config} <- configuration() do
        transaction = %{
          provider: :oidc,
          enterprise_connection_id: nil,
          state: random_value(),
          nonce: random_value(),
          pkce_verifier: random_value(),
          redirect_uri: redirect_uri,
          return_to: Keyword.get(opts, :return_to, @default_return_to),
          issued_at_unix: System.system_time(:second)
        }

        request =
          transaction
          |> Map.take([:state, :nonce, :pkce_verifier, :redirect_uri])
          |> Map.put(:config, config)

        case oidc_client().authorization_uri(request) do
          {:ok, authorization_uri} when is_binary(authorization_uri) ->
            case Identity.store_oidc_login_transaction(
                   transaction.issued_at_unix + @login_transaction_ttl_seconds
                 ) do
              {:ok, transaction_id} ->
                transaction = Map.put(transaction, :id, transaction_id)
                {:ok, %{authorization_uri: authorization_uri, transaction: transaction}}

              {:error, _reason} = error ->
                error
            end

          _provider_error ->
            {:error, :provider_unavailable}
        end
      end

    finalize_login_result(
      result,
      Keyword.get(opts, :trace_id),
      Keyword.get(opts, :source_surface, "web"),
      nil
    )
  end

  def begin_login(_redirect_uri, _opts), do: {:error, :invalid_redirect_uri}

  def begin_workos_login(connection_id, redirect_uri, opts \\ [])

  def begin_workos_login(connection_id, redirect_uri, opts)
      when is_binary(connection_id) and is_binary(redirect_uri) and is_list(opts) do
    state = random_value()
    issued_at_unix = System.system_time(:second)

    result =
      with {:ok, prepared} <-
             EnterpriseIdentity.prepare_workos_login(
               connection_id,
               redirect_uri,
               state,
               Keyword.get(opts, :workspace_id)
             ),
           {:ok, transaction_id} <-
             Identity.store_oidc_login_transaction(
               issued_at_unix + @login_transaction_ttl_seconds
             ) do
        transaction = %{
          id: transaction_id,
          provider: :workos,
          enterprise_connection_id: connection_id,
          workspace_id: prepared.workspace_id,
          state: state,
          redirect_uri: redirect_uri,
          return_to: Keyword.get(opts, :return_to, @default_return_to),
          issued_at_unix: issued_at_unix
        }

        {:ok,
         %{
           authorization_uri: prepared.authorization_uri,
           transaction: transaction
         }}
      end

    finalize_login_result(
      result,
      Keyword.get(opts, :trace_id),
      Keyword.get(opts, :source_surface, "web"),
      nil,
      "workos_sso"
    )
  end

  def begin_workos_login(_connection_id, _redirect_uri, opts) when is_list(opts) do
    finalize_login_result(
      {:error, :enterprise_connection_unavailable},
      Keyword.get(opts, :trace_id),
      Keyword.get(opts, :source_surface, "web"),
      nil,
      "workos_sso"
    )
  end

  def begin_workos_login(_connection_id, _redirect_uri, _opts),
    do: {:error, :enterprise_connection_unavailable}

  def complete_login(code, callback_state, %{id: transaction_id} = transaction, opts)
      when is_binary(transaction_id) and is_list(opts) do
    trace_id = Keyword.get(opts, :trace_id)
    source_surface = Keyword.get(opts, :source_surface, "web")

    with :ok <- Identity.consume_oidc_login_transaction(transaction_id),
         :ok <- validate_callback(code, callback_state, transaction),
         {:ok, config} <- configuration(),
         {:ok, claims} <- exchange(code, transaction, config),
         {:ok, linked} <-
           Identity.reconcile_oidc_identity_with_evidence(
             claims,
             provider: config.provider,
             provider_tenant: config.provider_tenant,
             account_linking_policy: config.account_linking_policy
           ) do
      result =
        with {:ok, scope} <-
               Authorization.resolve_login_scope(
                 linked.principal.id,
                 config.preferred_scope
               ),
             {:ok, issued} <-
               Identity.issue_human_session(
                 linked.principal,
                 linked.external_identity_link,
                 scope,
                 authentication_method: "oidc",
                 source_surface: source_surface,
                 trace_id: trace_id,
                 ttl_seconds: config.session_ttl_seconds
               ) do
          {:ok, Map.merge(issued, linked)}
        end

      finalize_login_result(result, trace_id, source_surface, linked)
    else
      {:error, reason, evidence} ->
        finalize_login_result({:error, reason}, trace_id, source_surface, evidence)

      {:error, _reason} = error ->
        finalize_login_result(error, trace_id, source_surface, nil)
    end
  end

  def complete_login(_code, _callback_state, _transaction, opts) when is_list(opts) do
    finalize_login_result(
      {:error, :invalid_login_transaction},
      Keyword.get(opts, :trace_id),
      Keyword.get(opts, :source_surface, "web"),
      nil
    )
  end

  def complete_login(_code, _callback_state, _transaction, _opts),
    do: {:error, :invalid_login_transaction}

  def complete_workos_login(code, callback_state, %{id: transaction_id} = transaction, opts)
      when is_binary(transaction_id) and is_list(opts) do
    trace_id = Keyword.get_lazy(opts, :trace_id, &Ecto.UUID.generate/0)
    source_surface = Keyword.get(opts, :source_surface, "web")

    with :ok <- Identity.consume_oidc_login_transaction(transaction_id),
         :ok <- validate_workos_callback(code, callback_state, transaction),
         {:ok, exchange} <-
           EnterpriseIdentity.exchange_workos_code(
             transaction.enterprise_connection_id,
             code,
             transaction.redirect_uri,
             transaction.workspace_id
           ),
         {:ok, linked} <-
           reconcile_workos_identity(
             exchange.profile,
             exchange.provider_organization_id
           ) do
      result =
        with :ok <-
               EnterpriseIdentity.validate_workos_provisioning(
                 exchange,
                 linked.principal.id
               ),
             {:ok, scope} <-
               Authorization.resolve_login_scope(linked.principal.id, %{
                 organization_id: exchange.organization_id,
                 workspace_id: exchange.workspace_id
               }),
             {:ok, issued} <-
               Identity.issue_human_session(
                 linked.principal,
                 linked.external_identity_link,
                 scope,
                 authentication_method: "workos_sso",
                 enterprise_connection_id: exchange.connection_id,
                 source_surface: source_surface,
                 trace_id: trace_id,
                 ttl_seconds: exchange.session_ttl_seconds
               ) do
          {:ok, Map.merge(issued, linked)}
        end

      finalize_login_result(result, trace_id, source_surface, linked, "workos_sso")
    else
      {:error, _reason} = error ->
        finalize_login_result(error, trace_id, source_surface, nil, "workos_sso")
    end
  end

  def complete_workos_login(_code, _callback_state, _transaction, opts)
      when is_list(opts) do
    finalize_login_result(
      {:error, :invalid_login_transaction},
      Keyword.get(opts, :trace_id),
      Keyword.get(opts, :source_surface, "web"),
      nil,
      "workos_sso"
    )
  end

  def complete_workos_login(_code, _callback_state, _transaction, _opts),
    do: {:error, :invalid_login_transaction}

  def complete_local_development_login(fixture_key, opts)
      when is_binary(fixture_key) and is_list(opts) do
    trace_id = Keyword.get_lazy(opts, :trace_id, &Ecto.UUID.generate/0)
    source_surface = Keyword.get(opts, :source_surface, "web")

    with :ok <- local_development_available(),
         {:ok, fixture} <- fetch_local_development_fixture(fixture_key),
         {:ok, linked} <- Identity.local_development_identity(fixture) do
      result =
        with :ok <- validate_local_development_identity(linked),
             {:ok, scope} <-
               Authorization.resolve_local_development_login_scope(
                 linked.principal.id,
                 fixture
               ),
             {:ok, issued} <-
               Identity.issue_human_session(
                 linked.principal,
                 linked.external_identity_link,
                 scope,
                 authentication_method: "local_development",
                 source_surface: source_surface,
                 trace_id: trace_id,
                 ttl_seconds: @default_session_ttl_seconds
               ) do
          {:ok, Map.merge(issued, linked)}
        end

      finalize_login_result(
        result,
        trace_id,
        source_surface,
        linked,
        "local_development"
      )
    else
      {:error, _reason} = error ->
        finalize_login_result(
          error,
          trace_id,
          source_surface,
          nil,
          "local_development"
        )
    end
  end

  def complete_local_development_login(_fixture_key, opts) when is_list(opts) do
    finalize_login_result(
      {:error, :local_development_fixture_missing},
      Keyword.get_lazy(opts, :trace_id, &Ecto.UUID.generate/0),
      Keyword.get(opts, :source_surface, "web"),
      nil,
      "local_development"
    )
  end

  def complete_local_development_login(_fixture_key, _opts),
    do: {:error, :local_development_fixture_missing}

  def resolve_session(session_id, opts \\ [])

  def resolve_session(session_id, opts) when is_list(opts) do
    opts = Keyword.put_new(opts, :source_surface, "web")

    case Identity.resolve_human_session(session_id, opts) do
      {:ok, session_context} ->
        with :ok <- validate_current_authentication_basis(session_context, opts) do
          validate_current_session_scope(session_context, opts)
        end

      {:error, _reason} = error ->
        error
    end
  end

  def resolve_session(_session_id, _opts), do: {:error, :invalid_session}

  def transient_storage_error?(reason), do: reason in @transient_storage_errors

  def oidc_available?, do: match?({:ok, _config}, configuration())
  def local_development_enabled?, do: LocalDevelopment.enabled?()
  def local_development_fixtures, do: LocalDevelopmentFixtures.all()
  def local_development_fixture(key), do: LocalDevelopmentFixtures.fetch(key)

  def logout(session_id, opts) when is_binary(session_id) and is_list(opts) do
    trace_id = Keyword.get(opts, :trace_id)
    post_logout_redirect_uri = Keyword.get(opts, :post_logout_redirect_uri)

    with {:ok, authentication_method} <-
           Identity.human_session_authentication_method(session_id),
         :ok <- Identity.revoke_human_session(session_id, trace_id: trace_id) do
      {:ok,
       %{
         authentication_method: authentication_method,
         provider_logout_uri: provider_logout_uri(authentication_method, post_logout_redirect_uri)
       }}
    end
  end

  def logout(_session_id, _opts), do: {:error, :invalid_session}

  def oidc_children do
    with {:ok, config} <- configuration(),
         OidccClient <- oidc_client() do
      [
        {Oidcc.ProviderConfiguration.Worker,
         %{issuer: config.issuer, name: OidccClient.provider_name()}}
      ]
    else
      _disabled_or_test_adapter -> []
    end
  end

  defp exchange(code, transaction, config) do
    request = %{
      config: config,
      code: code,
      redirect_uri: transaction.redirect_uri,
      nonce: transaction.nonce,
      pkce_verifier: transaction.pkce_verifier
    }

    case oidc_client().exchange(request) do
      {:ok, claims} when is_map(claims) -> {:ok, claims}
      _provider_error -> {:error, :provider_unavailable}
    end
  end

  defp validate_callback(code, callback_state, transaction)
       when is_binary(code) and is_binary(callback_state) and is_map(transaction) do
    validate_transaction(transaction, callback_state)
  end

  defp validate_callback(_code, _callback_state, _transaction),
    do: {:error, :invalid_login_transaction}

  defp validate_workos_callback(code, callback_state, transaction)
       when is_binary(code) and is_binary(callback_state) and is_map(transaction) do
    validate_workos_transaction(transaction, callback_state)
  end

  defp validate_workos_callback(_code, _callback_state, _transaction),
    do: {:error, :invalid_login_transaction}

  defp validate_transaction(
         %{
           id: id,
           state: state,
           nonce: nonce,
           pkce_verifier: pkce_verifier,
           redirect_uri: redirect_uri,
           issued_at_unix: issued_at_unix
         } = transaction,
         callback_state
       )
       when is_binary(id) and is_binary(state) and is_binary(nonce) and is_binary(pkce_verifier) and
              is_binary(redirect_uri) and is_integer(issued_at_unix) and
              is_binary(callback_state) do
    age = System.system_time(:second) - issued_at_unix

    if oidc_transaction?(transaction) and secure_state_match?(state, callback_state) and
         nonce != "" and pkce_verifier != "" and
         redirect_uri != "" and age >= 0 and age <= @login_transaction_ttl_seconds do
      :ok
    else
      {:error, :invalid_login_transaction}
    end
  end

  defp validate_transaction(_transaction, _callback_state),
    do: {:error, :invalid_login_transaction}

  defp validate_workos_transaction(
         %{
           id: id,
           provider: :workos,
           enterprise_connection_id: connection_id,
           workspace_id: workspace_id,
           state: state,
           redirect_uri: redirect_uri,
           issued_at_unix: issued_at_unix
         },
         callback_state
       )
       when is_binary(id) and is_binary(connection_id) and is_binary(workspace_id) and
              is_binary(state) and
              is_binary(redirect_uri) and is_integer(issued_at_unix) and
              is_binary(callback_state) do
    age = System.system_time(:second) - issued_at_unix

    if secure_state_match?(state, callback_state) and connection_id != "" and
         redirect_uri != "" and age >= 0 and age <= @login_transaction_ttl_seconds do
      :ok
    else
      {:error, :invalid_login_transaction}
    end
  end

  defp validate_workos_transaction(_transaction, _callback_state),
    do: {:error, :invalid_login_transaction}

  defp oidc_transaction?(%{provider: provider, enterprise_connection_id: connection_id}),
    do: provider == :oidc and is_nil(connection_id)

  defp oidc_transaction?(transaction),
    do: not Map.has_key?(transaction, :provider)

  defp secure_state_match?(expected, actual) when byte_size(expected) == byte_size(actual),
    do: :crypto.hash_equals(expected, actual)

  defp secure_state_match?(_expected, _actual), do: false

  defp reconcile_workos_identity(profile, provider_tenant) do
    case Identity.reconcile_workos_sso_identity(profile, provider_tenant) do
      {:ok, linked} -> {:ok, linked}
      {:review, _reason} -> {:error, :identity_review_required}
      {:error, _reason} = error -> error
    end
  end

  defp finalize_login_result(
         result,
         trace_id,
         source_surface,
         linked,
         authentication_method \\ "oidc"
       ) do
    case maybe_record_rejection(
           result,
           trace_id,
           source_surface,
           linked,
           authentication_method
         ) do
      :ok -> result
      {:error, _reason} = error -> error
    end
  end

  defp maybe_record_rejection(
         {:ok, _completed},
         _trace_id,
         _source_surface,
         _linked,
         _authentication_method
       ),
       do: :ok

  defp maybe_record_rejection(
         {:error, reason},
         trace_id,
         source_surface,
         linked,
         authentication_method
       )
       when is_binary(trace_id) and trace_id != "" and is_binary(source_surface) do
    attrs = %{
      event: "login",
      result: "rejected",
      reason: bounded_reason(reason),
      authentication_method: authentication_method,
      source_surface: source_surface,
      trace_id: trace_id
    }

    attrs =
      case linked do
        %{principal: principal, external_identity_link: external_identity_link} ->
          Map.merge(attrs, %{
            principal_id: principal.id,
            external_identity_link_id: external_identity_link.id
          })

        %{external_identity_link: %{principal_id: principal_id} = external_identity_link}
        when is_binary(principal_id) ->
          Map.merge(attrs, %{
            principal_id: principal_id,
            external_identity_link_id: external_identity_link.id
          })

        %{external_identity_link: external_identity_link} ->
          Map.put(attrs, :external_identity_link_id, external_identity_link.id)

        _identity_not_reconciled ->
          attrs
      end

    case Identity.record_authentication_event(attrs) do
      {:ok, _event} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp maybe_record_rejection(
         _result,
         _trace_id,
         _source_surface,
         _linked,
         _authentication_method
       ),
       do: :ok

  defp bounded_reason(reason)
       when reason in [
              :authentication_unavailable,
              :provider_unavailable,
              :invalid_login_transaction,
              :invalid_identity_claims,
              :unverified_identifier,
              :identity_review_required,
              :identity_disabled,
              :principal_disabled,
              :local_development_fixture_missing,
              :no_login_scope,
              :scope_selection_required,
              :invalid_scope,
              :identity_storage_unavailable,
              :authorization_storage_unavailable,
              :enterprise_connection_unavailable,
              :directory_provisioning_required,
              :enterprise_identity_storage_unavailable
            ],
       do: reason

  defp bounded_reason(_reason), do: :authentication_failed

  defp provider_logout_uri("oidc", post_logout_redirect_uri)
       when is_binary(post_logout_redirect_uri) do
    with {:ok, config} <- configuration(),
         {:ok, uri} <-
           oidc_client().logout_uri(%{
             config: config,
             post_logout_redirect_uri: post_logout_redirect_uri
           }) do
      uri
    else
      _unavailable_or_unsupported -> nil
    end
  end

  defp provider_logout_uri(_authentication_method, _post_logout_redirect_uri), do: nil

  defp validate_current_authentication_basis(
         %{
           authentication_method: "workos_sso",
           enterprise_connection_id: connection_id,
           organization_id: organization_id,
           workspace_id: workspace_id
         } = session_context,
         opts
       ) do
    case EnterpriseIdentity.validate_workos_session_basis(%{
           connection_id: connection_id,
           principal_id: session_context.principal_id,
           external_identity_link_id: session_context.external_identity_link_id,
           organization_id: organization_id,
           workspace_id: workspace_id
         }) do
      :ok ->
        :ok

      {:error, :enterprise_identity_storage_unavailable} = error ->
        error

      {:error, :enterprise_connection_unavailable} ->
        Identity.reject_human_session(session_context, "identity_disabled", opts)
    end
  end

  defp validate_current_authentication_basis(
         %{authentication_method: "local_development"} = session_context,
         opts
       ) do
    result =
      if LocalDevelopment.enabled?() do
        validate_exact_local_development_session(session_context)
      else
        {:error, :invalid_session}
      end

    case result do
      :ok ->
        :ok

      {:error, :identity_storage_unavailable} = error ->
        error

      {:error, _invalid_basis} ->
        Identity.reject_human_session(
          session_context,
          "identity_disabled",
          ensure_rejection_trace(opts)
        )
    end
  end

  defp validate_current_authentication_basis(_session_context, _opts), do: :ok

  defp validate_exact_local_development_session(session_context) do
    Enum.reduce_while(
      LocalDevelopmentFixtures.all(),
      {:error, :invalid_session},
      fn fixture, _not_matched ->
        case Identity.local_development_identity(fixture) do
          {:ok, linked} ->
            if linked.principal.id == session_context.principal_id and
                 linked.external_identity_link.id ==
                   session_context.external_identity_link_id and
                 linked.principal.status == "active" and
                 linked.external_identity_link.status == "active" and
                 linked.external_identity_link.linking_state == "linked" do
              {:halt, :ok}
            else
              {:cont, {:error, :invalid_session}}
            end

          {:error, :identity_storage_unavailable} = error ->
            {:halt, error}

          {:error, :local_development_fixture_missing} ->
            {:cont, {:error, :invalid_session}}
        end
      end
    )
  end

  defp ensure_rejection_trace(opts) do
    Keyword.put_new_lazy(opts, :trace_id, &Ecto.UUID.generate/0)
  end

  defp validate_current_session_scope(session_context, opts) do
    scope = %{
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id
    }

    case Authorization.resolve_login_scope(session_context.principal_id, scope) do
      {:ok, ^scope} ->
        {:ok, session_context}

      {:error, :authorization_storage_unavailable} = error ->
        error

      {:error, _invalid_scope} ->
        Identity.reject_human_session(session_context, "invalid_scope", opts)
    end
  end

  defp configuration do
    config = Application.get_env(:office_graph, :human_oidc, [])
    issuer = config[:issuer]
    client_id = config[:client_id]
    client_secret = config[:client_secret]
    account_linking_policy = account_linking_policy(config[:account_linking_policy])
    preferred_scope = config[:preferred_scope]
    session_ttl_seconds = session_ttl_seconds(config[:session_ttl_seconds])

    if present?(issuer) and present?(client_id) and present?(client_secret) and
         account_linking_policy == :verified_email_existing_principal and
         valid_preferred_scope?(preferred_scope) and
         is_integer(session_ttl_seconds) and session_ttl_seconds > 0 do
      {:ok,
       %{
         provider: "authentik",
         provider_tenant: issuer,
         issuer: issuer,
         client_id: client_id,
         client_secret: client_secret,
         account_linking_policy: account_linking_policy,
         preferred_scope: preferred_scope,
         session_ttl_seconds: session_ttl_seconds
       }}
    else
      {:error, :authentication_unavailable}
    end
  end

  defp local_development_available do
    if LocalDevelopment.enabled?() do
      :ok
    else
      {:error, :authentication_unavailable}
    end
  end

  defp fetch_local_development_fixture(fixture_key) do
    case LocalDevelopmentFixtures.fetch(fixture_key) do
      {:ok, fixture} -> {:ok, fixture}
      :error -> {:error, :local_development_fixture_missing}
    end
  end

  defp validate_local_development_identity(%{
         principal: %{kind: "human", status: "active"},
         external_identity_link: %{status: "active", linking_state: "linked"}
       }),
       do: :ok

  defp validate_local_development_identity(_disabled_or_drifted),
    do: {:error, :identity_disabled}

  defp oidc_client do
    Application.get_env(
      :office_graph,
      :human_oidc_client,
      OidccClient
    )
  end

  defp valid_preferred_scope?(nil), do: true

  defp valid_preferred_scope?(%{
         organization_id: organization_id,
         workspace_id: workspace_id
       }),
       do: present?(organization_id) and present?(workspace_id)

  defp valid_preferred_scope?(_preferred_scope), do: false

  defp account_linking_policy(:verified_email_existing_principal),
    do: :verified_email_existing_principal

  defp account_linking_policy("verified_email_existing_principal"),
    do: :verified_email_existing_principal

  defp account_linking_policy(_unsupported), do: :invalid

  defp session_ttl_seconds(nil), do: @default_session_ttl_seconds
  defp session_ttl_seconds(seconds) when is_integer(seconds) and seconds > 0, do: seconds

  defp session_ttl_seconds(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds > 0 -> seconds
      _invalid -> :invalid
    end
  end

  defp session_ttl_seconds(_invalid), do: :invalid

  defp random_value do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
