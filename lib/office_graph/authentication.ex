defmodule OfficeGraph.Authentication do
  @moduledoc """
  Public boundary for human OIDC login, session issuance, and logout.
  """

  use Boundary,
    deps: [OfficeGraph.Authorization, OfficeGraph.Identity],
    exports: [OidcClient]

  alias OfficeGraph.{Authorization, Identity}
  alias OfficeGraph.Authentication.OidcClient.Oidcc, as: OidccClient

  @login_transaction_ttl_seconds 10 * 60
  @default_return_to "/operator"
  @default_session_ttl_seconds 8 * 60 * 60

  def begin_login(redirect_uri, opts \\ [])

  def begin_login(redirect_uri, opts) when is_binary(redirect_uri) and is_list(opts) do
    with {:ok, config} <- configuration() do
      transaction = %{
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
          {:ok, %{authorization_uri: authorization_uri, transaction: transaction}}

        _provider_error ->
          {:error, :provider_unavailable}
      end
    end
  end

  def begin_login(_redirect_uri, _opts), do: {:error, :invalid_redirect_uri}

  def complete_login(code, callback_state, transaction, opts) when is_list(opts) do
    trace_id = Keyword.get(opts, :trace_id)
    source_surface = Keyword.get(opts, :source_surface, "web")

    with :ok <- validate_callback(code, callback_state, transaction),
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

      maybe_record_rejection(result, trace_id, source_surface, linked)
      result
    else
      {:error, reason, evidence} ->
        maybe_record_rejection({:error, reason}, trace_id, source_surface, evidence)
        {:error, reason}

      {:error, _reason} = error ->
        maybe_record_rejection(error, trace_id, source_surface, nil)
        error
    end
  end

  def complete_login(_code, _callback_state, _transaction, _opts),
    do: {:error, :invalid_login_transaction}

  def resolve_session(session_id, opts \\ []),
    do: Identity.resolve_human_session(session_id, opts)

  def logout(session_id, opts) when is_binary(session_id) and is_list(opts) do
    trace_id = Keyword.get(opts, :trace_id)
    post_logout_redirect_uri = Keyword.get(opts, :post_logout_redirect_uri)

    with :ok <- Identity.revoke_human_session(session_id, trace_id: trace_id) do
      {:ok,
       %{
         provider_logout_uri: provider_logout_uri(post_logout_redirect_uri)
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

  defp validate_transaction(
         %{
           state: state,
           nonce: nonce,
           pkce_verifier: pkce_verifier,
           redirect_uri: redirect_uri,
           issued_at_unix: issued_at_unix
         },
         callback_state
       )
       when is_binary(state) and is_binary(nonce) and is_binary(pkce_verifier) and
              is_binary(redirect_uri) and is_integer(issued_at_unix) and
              is_binary(callback_state) do
    age = System.system_time(:second) - issued_at_unix

    if secure_state_match?(state, callback_state) and nonce != "" and pkce_verifier != "" and
         redirect_uri != "" and age >= 0 and age <= @login_transaction_ttl_seconds do
      :ok
    else
      {:error, :invalid_login_transaction}
    end
  end

  defp validate_transaction(_transaction, _callback_state),
    do: {:error, :invalid_login_transaction}

  defp secure_state_match?(expected, actual) when byte_size(expected) == byte_size(actual),
    do: :crypto.hash_equals(expected, actual)

  defp secure_state_match?(_expected, _actual), do: false

  defp maybe_record_rejection({:ok, _completed}, _trace_id, _source_surface, _linked), do: :ok

  defp maybe_record_rejection({:error, reason}, trace_id, source_surface, linked)
       when is_binary(trace_id) and trace_id != "" and is_binary(source_surface) do
    attrs = %{
      event: "login",
      result: "rejected",
      reason: bounded_reason(reason),
      authentication_method: "oidc",
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

    Identity.record_authentication_event(attrs)

    :ok
  end

  defp maybe_record_rejection(_result, _trace_id, _source_surface, _linked), do: :ok

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
              :no_login_scope,
              :scope_selection_required,
              :invalid_scope,
              :identity_storage_unavailable,
              :authorization_storage_unavailable
            ],
       do: reason

  defp bounded_reason(_reason), do: :authentication_failed

  defp provider_logout_uri(post_logout_redirect_uri) when is_binary(post_logout_redirect_uri) do
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

  defp provider_logout_uri(_post_logout_redirect_uri), do: nil

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
