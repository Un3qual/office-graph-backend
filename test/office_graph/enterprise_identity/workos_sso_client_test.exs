defmodule OfficeGraph.EnterpriseIdentity.WorkOSSsoClientTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.HTTPClient.Httpc, as: WorkOSHttpc
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

  test "production HTTP requests verify TLS and receive successful bodies through a controlled stream" do
    assert {:module, :httpc} = :code.ensure_loaded(:httpc)
    parent = self()
    tracer = spawn(fn -> forward_trace_messages(parent) end)
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({:httpc, :request, 4}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({:httpc, :request, 4}, false, [])
      :erlang.trace(self(), false, [:call])
      Process.exit(tracer, :normal)
    end)

    assert {:error, :network_error} =
             WorkOSHttpc.request(:get, "https://127.0.0.1:1/workos", %{}, nil)

    assert_receive {:captured_trace,
                    {:trace, _pid, :call,
                     {:httpc, :request, [_method, _request, http_options, response_options]}}}

    ssl_options = Keyword.fetch!(http_options, :ssl)

    assert ssl_options[:verify] == :verify_peer
    assert [_first_ca | _rest] = ssl_options[:cacerts]

    assert is_function(
             get_in(ssl_options, [:customize_hostname_check, :match_fun]),
             2
           )

    assert response_options[:sync] == false
    assert response_options[:stream] == {:self, :once}
    assert response_options[:receiver] == self()
  end

  test "production HTTP stream rejects declared and accumulated bodies over the limit" do
    assert {:error, :network_error} =
             receive_http_stream(
               [{~c"content-length", ~c"6"}],
               [],
               maximum_bytes: 5
             )

    assert {:error, :network_error} =
             receive_http_stream(
               [{~c"transfer-encoding", ~c"chunked"}],
               ["abc", "def"],
               maximum_bytes: 5
             )

    assert {:ok, %{status: 200, headers: headers, body: "abcde"}} =
             receive_http_stream(
               [
                 {~c"content-length", ~c"5"},
                 {~c"x-workos-request-id", ~c"request-1"}
               ],
               ["abc", "de"],
               maximum_bytes: 5
             )

    assert headers["content-length"] == "5"
    assert headers["x-workos-request-id"] == "request-1"
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

  defp receive_http_stream(start_headers, chunks, opts) do
    request_id = make_ref()
    parent = self()

    task =
      Task.async(fn ->
        send(parent, {:stream_receiver, self()})

        WorkOSHttpc.receive_stream(
          request_id,
          Keyword.fetch!(opts, :maximum_bytes),
          1_000
        )
      end)

    assert_receive {:stream_receiver, receiver}
    handler = spawn(fn -> discard_stream_control_messages() end)
    send(receiver, {:http, {request_id, :stream_start, start_headers, handler}})

    Enum.each(chunks, fn chunk ->
      send(receiver, {:http, {request_id, :stream, chunk}})
    end)

    send(receiver, {:http, {request_id, :stream_end, []}})
    result = Task.await(task)
    send(handler, :stop)
    result
  end

  defp discard_stream_control_messages do
    receive do
      :stop -> :ok
      _message -> discard_stream_control_messages()
    end
  end

  defp forward_trace_messages(parent) do
    receive do
      message ->
        send(parent, {:captured_trace, message})
        forward_trace_messages(parent)
    end
  end
end
