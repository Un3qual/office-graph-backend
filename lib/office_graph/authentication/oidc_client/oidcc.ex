defmodule OfficeGraph.Authentication.OidcClient.Oidcc do
  @moduledoc false

  @behaviour OfficeGraph.Authentication.OidcClient

  @provider_name OfficeGraph.Authentication.OidcProvider

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
      {:ok, merge_validated_claims(id_claims, userinfo)}
    else
      _provider_error -> {:error, :provider_unavailable}
    end
  end

  @doc false
  def merge_validated_claims(id_claims, userinfo)
      when is_map(id_claims) and is_map(userinfo) do
    id_claims =
      if Map.has_key?(userinfo, "email") do
        Map.delete(id_claims, "email_verified")
      else
        id_claims
      end

    Map.merge(id_claims, userinfo)
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
  end
end
