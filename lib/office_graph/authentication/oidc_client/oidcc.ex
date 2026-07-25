defmodule OfficeGraph.Authentication.OidcClient.Oidcc do
  @moduledoc false

  @behaviour OfficeGraph.Authentication.OidcClient

  @provider_name OfficeGraph.Authentication.OidcProvider
  @provider_exceptions [
    ArgumentError,
    FunctionClauseError,
    KeyError,
    MatchError,
    RuntimeError
  ]

  def provider_name, do: @provider_name

  @impl true
  def authorization_uri(%{
        config: config,
        redirect_uri: redirect_uri,
        state: state,
        nonce: nonce,
        pkce_verifier: pkce_verifier
      }) do
    Oidcc.create_redirect_url(
      @provider_name,
      config.client_id,
      config.client_secret,
      %{
        redirect_uri: redirect_uri,
        state: state,
        nonce: nonce,
        pkce_verifier: pkce_verifier,
        require_pkce: true,
        scopes: ["openid", "profile", "email"]
      }
    )
  rescue
    _provider_error in @provider_exceptions -> {:error, :provider_unavailable}
  catch
    _kind, _reason -> {:error, :provider_unavailable}
  end

  @impl true
  def exchange(%{
        config: config,
        code: code,
        redirect_uri: redirect_uri,
        nonce: nonce,
        pkce_verifier: pkce_verifier
      }) do
    with {:ok, %Oidcc.Token{id: %Oidcc.Token.Id{claims: id_claims}} = token} <-
           Oidcc.retrieve_token(
             code,
             @provider_name,
             config.client_id,
             config.client_secret,
             %{
               redirect_uri: redirect_uri,
               nonce: nonce,
               pkce_verifier: pkce_verifier,
               require_pkce: true
             }
           ),
         subject when is_binary(subject) <- Map.get(id_claims, "sub"),
         {:ok, userinfo} <-
           Oidcc.retrieve_userinfo(
             token,
             @provider_name,
             config.client_id,
             config.client_secret,
             %{}
           ) do
      {:ok, Map.merge(id_claims, userinfo)}
    else
      _provider_error -> {:error, :provider_unavailable}
    end
  rescue
    _provider_error in @provider_exceptions -> {:error, :provider_unavailable}
  catch
    _kind, _reason -> {:error, :provider_unavailable}
  end

  @impl true
  def logout_uri(%{
        config: config,
        post_logout_redirect_uri: post_logout_redirect_uri
      }) do
    Oidcc.initiate_logout_url(
      :undefined,
      @provider_name,
      config.client_id,
      %{post_logout_redirect_uri: post_logout_redirect_uri}
    )
  rescue
    _provider_error in @provider_exceptions -> {:error, :provider_unavailable}
  catch
    _kind, _reason -> {:error, :provider_unavailable}
  end
end
