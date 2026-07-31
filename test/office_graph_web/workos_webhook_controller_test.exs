defmodule OfficeGraphWeb.WorkOSWebhookControllerTest do
  use OfficeGraphWeb.ConnCase, async: false

  @moduletag :unauthenticated

  defmodule SecretStore do
    @behaviour OfficeGraph.EnterpriseIdentity.SecretStore

    @impl true
    def resolve("test-secret://workos/controller"), do: {:ok, "controller-secret"}
    def resolve(_reference), do: {:error, :secret_not_found}
  end

  setup do
    original_config = Application.get_env(:office_graph, :workos_enterprise)
    original_store = Application.get_env(:office_graph, :workos_secret_store)

    Application.put_env(:office_graph, :workos_enterprise,
      webhook_secret_reference: "test-secret://workos/controller"
    )

    Application.put_env(:office_graph, :workos_secret_store, SecretStore)

    on_exit(fn ->
      restore_env(:workos_enterprise, original_config)
      restore_env(:workos_secret_store, original_store)
    end)

    :ok
  end

  test "maps invalid WorkOS signatures without exposing internals", %{conn: conn} do
    conn =
      conn
      |> put_req_header(
        "workos-signature",
        "t=0,v1=" <> String.duplicate("0", 64)
      )
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/webhooks/workos", ~s({"id":"event_invalid"}))

    assert %{"error" => %{"code" => "invalid_signature"}} = json_response(conn, 401)
  end

  test "verifies the WorkOS signature before attempting JSON decoding", %{conn: conn} do
    conn =
      conn
      |> put_req_header(
        "workos-signature",
        "t=0,v1=" <> String.duplicate("0", 64)
      )
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/webhooks/workos", ~s({"not-valid-json"))

    assert %{"error" => %{"code" => "invalid_signature"}} = json_response(conn, 401)
  end

  test "rejects oversized WorkOS bodies before JSON decoding", %{conn: conn} do
    conn =
      conn
      |> put_req_header(
        "workos-signature",
        "t=0,v1=" <> String.duplicate("0", 64)
      )
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/webhooks/workos", String.duplicate("x", 1_000_001))

    assert %{"error" => %{"code" => "invalid_delivery"}} = json_response(conn, 422)
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)
end
