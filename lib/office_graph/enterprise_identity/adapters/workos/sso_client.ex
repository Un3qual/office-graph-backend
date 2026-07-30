defmodule OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.SsoClient do
  @moduledoc false

  @behaviour OfficeGraph.EnterpriseIdentity.EnterpriseSsoClient

  alias OfficeGraph.EnterpriseIdentity.SecretStore

  @maximum_response_bytes 1_000_000
  @authorization_path "/sso/authorize"
  @token_path "/sso/token"

  @impl true
  def authorization_uri(%{
        config: config,
        redirect_uri: redirect_uri,
        state: state
      }) do
    with {:ok, config} <- validate_configuration(config),
         :ok <- validate_present(redirect_uri),
         :ok <- validate_present(state) do
      query =
        URI.encode_query(%{
          "client_id" => config.client_id,
          "organization" => config.provider_organization_id,
          "redirect_uri" => redirect_uri,
          "response_type" => "code",
          "state" => state
        })

      {:ok, endpoint(config.api_base_url, @authorization_path) <> "?" <> query}
    end
  end

  def authorization_uri(_request), do: {:error, :invalid_configuration}

  @impl true
  def exchange(%{
        config: config,
        code: code,
        redirect_uri: redirect_uri
      }) do
    with {:ok, config} <- validate_configuration(config),
         :ok <- validate_present(code),
         :ok <- validate_present(redirect_uri),
         {:ok, api_key} <- SecretStore.resolve(config.api_key_reference),
         {:ok, response} <-
           http_client().request(
             :post,
             endpoint(config.api_base_url, @token_path),
             %{
               "accept" => "application/json",
               "authorization" => "Bearer #{api_key}",
               "content-type" => "application/x-www-form-urlencoded"
             },
             token_request_body(config, api_key, code, redirect_uri)
           ),
         {:ok, payload} <- decode_success(response),
         {:ok, profile} <- normalize_profile(payload, config.provider_organization_id) do
      {:ok, profile}
    else
      {:error, reason}
      when reason in [
             :invalid_configuration,
             :invalid_profile,
             :provider_unavailable
           ] ->
        {:error, reason}

      {:error, _secret_or_network_error} ->
        {:error, :provider_unavailable}
    end
  end

  def exchange(_request), do: {:error, :invalid_configuration}

  defp token_request_body(config, api_key, code, redirect_uri) do
    URI.encode_query(%{
      "client_id" => config.client_id,
      "client_secret" => api_key,
      "code" => code,
      "grant_type" => "authorization_code",
      "redirect_uri" => redirect_uri
    })
  end

  defp decode_success(%{status: 200, body: body})
       when is_binary(body) and byte_size(body) <= @maximum_response_bytes do
    case Jason.decode(body) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _invalid_json -> {:error, :invalid_profile}
    end
  end

  defp decode_success(_response), do: {:error, :provider_unavailable}

  defp normalize_profile(
         %{
           "profile" =>
             %{
               "email" => email,
               "organization_id" => provider_organization_id,
               "connection_id" => connection_id
             } = profile
         },
         provider_organization_id
       )
       when is_binary(email) and is_binary(connection_id) do
    subject_id = profile["idp_id"] || profile["id"]
    email = email |> String.trim() |> String.downcase()

    if present?(subject_id) and present?(connection_id) and present?(email) do
      {:ok,
       %{
         subject: "#{connection_id}:#{String.trim(subject_id)}",
         idp_id: String.trim(subject_id),
         verified_email: email,
         first_name: optional_string(profile["first_name"]),
         last_name: optional_string(profile["last_name"]),
         provider_organization_id: provider_organization_id,
         provider_connection_id: connection_id
       }}
    else
      {:error, :invalid_profile}
    end
  end

  defp normalize_profile(_payload, _provider_organization_id),
    do: {:error, :invalid_profile}

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 255)
    end
  end

  defp optional_string(_value), do: nil

  defp validate_configuration(config) when is_map(config) do
    with :ok <- validate_https_base_url(config[:api_base_url]),
         :ok <- validate_present(config[:api_key_reference]),
         :ok <- validate_present(config[:client_id]),
         :ok <- validate_present(config[:provider_organization_id]) do
      {:ok,
       %{
         api_base_url: String.trim_trailing(config.api_base_url, "/"),
         api_key_reference: config.api_key_reference,
         client_id: config.client_id,
         provider_organization_id: config.provider_organization_id
       }}
    end
  end

  defp validate_configuration(_config), do: {:error, :invalid_configuration}

  defp validate_https_base_url(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{
        scheme: "https",
        host: host,
        query: nil,
        fragment: nil,
        userinfo: nil
      }
      when is_binary(host) and host != "" ->
        :ok

      _invalid ->
        {:error, :invalid_configuration}
    end
  end

  defp validate_https_base_url(_value), do: {:error, :invalid_configuration}

  defp validate_present(value) when is_binary(value) do
    if present?(value), do: :ok, else: {:error, :invalid_configuration}
  end

  defp validate_present(_value), do: {:error, :invalid_configuration}

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp endpoint(base_url, path), do: String.trim_trailing(base_url, "/") <> path

  defp http_client do
    Application.fetch_env!(:office_graph, :workos_http_client)
  end
end
