defmodule OfficeGraph.EnterpriseIdentity.WorkOSSsoClientTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.HTTPClient.ReqClient, as: WorkOSHTTP
  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.SsoClient

  @base_url "https://api.workos.test"
  @api_key_reference "test-secret://workos/api-key"

  defmodule HTTPClient do
    @behaviour OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.HTTPClient

    @impl true
    def request(method, url, headers, body) do
      send(self(), {:workos_http_request, method, url, headers, body})
      Process.get({__MODULE__, :response}, {:error, :network_error})
    end
  end

  defmodule SecretStore do
    @behaviour OfficeGraph.EnterpriseIdentity.SecretStore

    @impl true
    def resolve("test-secret://workos/api-key"), do: {:ok, "sk_test_secret"}
    def resolve(_reference), do: {:error, :secret_not_found}
  end

  setup do
    original_http = Application.get_env(:office_graph, :workos_http_client)
    original_secret_store = Application.get_env(:office_graph, :workos_secret_store)

    Application.put_env(:office_graph, :workos_http_client, HTTPClient)
    Application.put_env(:office_graph, :workos_secret_store, SecretStore)

    on_exit(fn ->
      restore_env(:workos_http_client, original_http)
      restore_env(:workos_secret_store, original_secret_store)
    end)

    :ok
  end

  test "builds an organization-bound standalone SSO authorization URL" do
    assert {:ok, authorization_uri} =
             SsoClient.authorization_uri(%{
               config: configuration(),
               redirect_uri: "https://office-graph.test/auth/workos/callback",
               state: "state-value"
             })

    uri = URI.parse(authorization_uri)
    query = URI.decode_query(uri.query)

    assert uri.scheme == "https"
    assert uri.host == "api.workos.test"
    assert uri.path == "/sso/authorize"

    assert query == %{
             "client_id" => "client_01",
             "organization" => "org_01",
             "redirect_uri" => "https://office-graph.test/auth/workos/callback",
             "response_type" => "code",
             "state" => "state-value"
           }

    refute authorization_uri =~ "sk_test_secret"
  end

  test "exchanges a code and returns only normalized stable identity fields" do
    Process.put(
      {HTTPClient, :response},
      {:ok,
       %{
         status: 200,
         headers: %{},
         body:
           Jason.encode!(%{
             "access_token" => "access-token-must-not-escape",
             "profile" => %{
               "id" => "prof_01",
               "idp_id" => "idp_user_01",
               "email" => " Person@Example.COM ",
               "first_name" => "Ada",
               "last_name" => "Lovelace",
               "organization_id" => "org_01",
               "connection_id" => "conn_01",
               "raw_attributes" => %{"groups" => ["administrator"]}
             }
           })
       }}
    )

    assert {:ok, profile} =
             SsoClient.exchange(%{
               config: configuration(),
               code: "authorization-code",
               redirect_uri: "https://office-graph.test/auth/workos/callback"
             })

    assert profile == %{
             subject: "conn_01:idp_user_01",
             idp_id: "idp_user_01",
             verified_email: "person@example.com",
             first_name: "Ada",
             last_name: "Lovelace",
             provider_organization_id: "org_01",
             provider_connection_id: "conn_01"
           }

    assert_received {:workos_http_request, :post, "#{@base_url}/sso/token", headers, body}
    assert headers["authorization"] == "Bearer sk_test_secret"
    assert headers["content-type"] == "application/x-www-form-urlencoded"

    assert URI.decode_query(body) == %{
             "client_id" => "client_01",
             "client_secret" => "sk_test_secret",
             "code" => "authorization-code",
             "grant_type" => "authorization_code",
             "redirect_uri" => "https://office-graph.test/auth/workos/callback"
           }

    refute inspect(profile) =~ "access-token"
    refute inspect(profile) =~ "administrator"
  end

  test "rejects a profile from a different WorkOS organization" do
    Process.put(
      {HTTPClient, :response},
      {:ok,
       %{
         status: 200,
         headers: %{},
         body:
           Jason.encode!(%{
             "profile" => %{
               "idp_id" => "idp_user_01",
               "email" => "person@example.com",
               "organization_id" => "org_other",
               "connection_id" => "conn_01"
             }
           })
       }}
    )

    assert {:error, :invalid_profile} =
             SsoClient.exchange(%{
               config: configuration(),
               code: "authorization-code",
               redirect_uri: "https://office-graph.test/auth/workos/callback"
             })
  end

  test "rejects oversized individual SSO profile fields" do
    valid_profile = %{
      "idp_id" => "idp_user_01",
      "email" => "person@example.com",
      "first_name" => "Ada",
      "last_name" => "Lovelace",
      "organization_id" => "org_01",
      "connection_id" => "conn_01"
    }

    for {field, value} <- [
          {"idp_id", String.duplicate("i", 256)},
          {"email", String.duplicate("e", 321)},
          {"first_name", String.duplicate("f", 256)},
          {"last_name", String.duplicate("l", 256)},
          {"connection_id", String.duplicate("c", 256)}
        ] do
      Process.put(
        {HTTPClient, :response},
        {:ok,
         %{
           status: 200,
           headers: %{},
           body: Jason.encode!(%{"profile" => Map.put(valid_profile, field, value)})
         }}
      )

      assert {:error, :invalid_profile} =
               SsoClient.exchange(%{
                 config: configuration(),
                 code: "authorization-code",
                 redirect_uri: "https://office-graph.test/auth/workos/callback"
               })
    end
  end

  test "rejects non-HTTPS WorkOS API configuration" do
    config = %{configuration() | api_base_url: "http://api.workos.test"}

    assert {:error, :invalid_configuration} =
             SsoClient.authorization_uri(%{
               config: config,
               redirect_uri: "https://office-graph.test/auth/workos/callback",
               state: "state-value"
             })

    assert {:error, :invalid_configuration} =
             SsoClient.exchange(%{
               config: config,
               code: "authorization-code",
               redirect_uri: "https://office-graph.test/auth/workos/callback"
             })
  end

  test "production HTTP transport returns the exact bounded response contract" do
    {listener, port, server} =
      serve_response([
        "HTTP/1.1 200 OK\r\n",
        "content-length: 5\r\n",
        "x-workos-request-id: request-1\r\n",
        "connection: close\r\n\r\n",
        "abcde"
      ])

    on_exit(fn -> :gen_tcp.close(listener) end)

    assert {:ok, %{status: 200, headers: headers, body: "abcde"}} =
             WorkOSHTTP.request(:get, "http://127.0.0.1:#{port}", %{}, nil)

    assert headers["content-length"] == "5"
    assert headers["x-workos-request-id"] == "request-1"
    Task.await(server)
  end

  test "production HTTP transport stops oversized non-success responses while receiving them" do
    maximum_bytes = 1_000_000
    first_body_part = :binary.copy("a", maximum_bytes + 1)
    remaining_body = :binary.copy("b", maximum_bytes - 1)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])

    {:ok, {_address, port}} = :inet.sockname(listener)
    parent = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        :ok = receive_request_headers(socket, "")

        :ok =
          :gen_tcp.send(socket, [
            "HTTP/1.1 500 Internal Server Error\r\n",
            "connection: close\r\n\r\n",
            first_body_part
          ])

        closed_before_remainder? =
          case :gen_tcp.recv(socket, 0, 1_000) do
            {:error, :closed} -> true
            {:error, :timeout} -> false
          end

        send(parent, {:closed_before_remainder, closed_before_remainder?})

        unless closed_before_remainder? do
          :ok = :gen_tcp.send(socket, remaining_body)
        end

        :gen_tcp.close(socket)
      end)

    on_exit(fn -> :gen_tcp.close(listener) end)

    assert {:error, :network_error} =
             WorkOSHTTP.request(:get, "http://127.0.0.1:#{port}", %{}, nil)

    assert_receive {:closed_before_remainder, true}
    Task.await(server)
  end

  defp configuration do
    %{
      api_base_url: @base_url,
      api_key_reference: @api_key_reference,
      client_id: "client_01",
      provider_organization_id: "org_01"
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)

  defp serve_response(response) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])

    {:ok, {_address, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        :ok = receive_request_headers(socket, "")
        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
      end)

    {listener, port, server}
  end

  defp receive_request_headers(socket, received) do
    if String.contains?(received, "\r\n\r\n") do
      :ok
    else
      case :gen_tcp.recv(socket, 0, 1_000) do
        {:ok, chunk} -> receive_request_headers(socket, received <> chunk)
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
