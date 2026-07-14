defmodule OfficeGraphWeb.GitHubWebhookControllerTest do
  use OfficeGraphWeb.ConnCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration}
  alias OfficeGraph.GitHubIntegration.SecretStore.TestAdapter

  test "accepts the exact signed raw body promptly and returns duplicate safely", %{conn: conn} do
    context = installation_context("controller")
    delivery_id = "delivery-controller-#{Ecto.UUID.generate()}"

    body =
      Jason.encode!(%{
        "action" => "submitted",
        "installation" => %{"id" => context.external_installation_id},
        "review" => %{"id" => 99}
      })

    headers = signed_headers(delivery_id, "pull_request_review", body, context.webhook_secret)

    first = post_raw(conn, body, headers)
    assert %{"status" => "accepted"} = json_response(first, 202)

    replay = post_raw(build_conn(), body, headers)
    assert %{"status" => "duplicate"} = json_response(replay, 202)
  end

  test "maps invalid, unknown, and unsupported deliveries without internal details", %{conn: conn} do
    context = installation_context("controller-errors")

    body = Jason.encode!(%{"installation" => %{"id" => context.external_installation_id}})

    invalid =
      post_raw(conn, body, %{
        "x-github-delivery" => "invalid-controller",
        "x-github-event" => "pull_request",
        "x-hub-signature-256" => "sha256=invalid"
      })

    assert %{"error" => %{"code" => "invalid_signature"}} = json_response(invalid, 401)

    unsupported_headers =
      signed_headers("unsupported-controller", "push", body, context.webhook_secret)

    assert %{"error" => %{"code" => "unsupported_event"}} =
             conn
             |> recycle()
             |> post_raw(body, unsupported_headers)
             |> json_response(422)
  end

  defp post_raw(conn, body, headers) do
    conn =
      Enum.reduce(headers, conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/webhooks/github", body)
  end

  defp installation_context(label) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    external_installation_id = System.unique_integer([:positive])
    webhook_reference = "test-secret://github/#{label}/webhook"
    webhook_secret = "controller-secret-#{label}"

    assert {:ok, _bound} =
             GitHubIntegration.bind_installation(bootstrap.session, %{
               idempotency_key: "bind-webhook-#{label}",
               external_installation_id: external_installation_id,
               workspace_id: nil,
               app_slug: "office-graph",
               account_login: "Un3qual",
               account_type: "organization",
               service_principal_email: "github-service-#{label}@office-graph.local",
               webhook_principal_email: "github-webhook-#{label}@office-graph.local",
               webhook_secret_reference: webhook_reference,
               app_private_key_reference: "test-secret://github/#{label}/private-key",
               permissions: [%{name: "pull_requests", access_level: "write"}]
             })

    TestAdapter.put(%{webhook_reference => webhook_secret})

    %{
      external_installation_id: external_installation_id,
      webhook_secret: webhook_secret
    }
  end

  defp signed_headers(delivery_id, event, body, secret) do
    signature = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

    %{
      "x-github-delivery" => delivery_id,
      "x-github-event" => event,
      "x-hub-signature-256" => "sha256=#{signature}"
    }
  end
end
