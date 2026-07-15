defmodule OfficeGraph.GitHubIntegration.WebhookReceiptTest do
  use OfficeGraph.DataCase, async: false

  import Ecto.Query

  require Ash.Query

  alias OfficeGraph.{Foundation, GitHubIntegration, Integrations, Repo}
  alias OfficeGraph.DurableDelivery.DomainEvent
  alias OfficeGraph.GitHubIntegration.{SecretStore.TestAdapter, WebhookReceipt, WebhookWorker}
  alias OfficeGraph.Integrations.RawArchive
  alias OfficeGraph.Operations.OperationCorrelation

  defmodule UnavailableSecretStore do
    @behaviour OfficeGraph.GitHubIntegration.SecretStore

    @impl true
    def fetch(_reference, _scope), do: {:error, :unavailable}
  end

  test "valid supported deliveries archive and enqueue exactly once" do
    context = installation_context("accepted")
    delivery_id = "delivery-#{Ecto.UUID.generate()}"
    body = payload(context.external_installation_id)
    headers = signed_headers(delivery_id, "pull_request", body, context.webhook_secret)

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)
    assert {:ok, :duplicate} = WebhookReceipt.accept(headers, body)

    assert count_archives(delivery_id) == 1
    assert count_operations(delivery_id) == 1
    assert count_events(delivery_id) == 1
    assert count_webhook_jobs(delivery_id) == 1

    archive =
      RawArchive
      |> Ash.Query.filter(external_delivery_id == ^delivery_id)
      |> Ash.read_one!(authorize?: false)

    assert archive.body == body
    assert archive.archive_kind == "provider_delivery"
    refute inspect(archive.metadata) =~ context.webhook_secret

    assert {:ok, scoped_archive} =
             Integrations.provider_delivery_archive(
               context.organization_id,
               nil,
               archive.id,
               delivery_id
             )

    assert scoped_archive.id == archive.id
  end

  test "replayed deliveries do not recreate webhook jobs after pruning" do
    context = installation_context("pruned-job-replay")
    delivery_id = "delivery-#{Ecto.UUID.generate()}"
    body = payload(context.external_installation_id)
    headers = signed_headers(delivery_id, "pull_request", body, context.webhook_secret)

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    WebhookWorker
    |> inspect()
    |> then(fn worker ->
      from(job in Oban.Job,
        where: job.worker == ^worker and fragment("?->>'delivery_id'", job.args) == ^delivery_id
      )
    end)
    |> Repo.one!()
    |> Repo.delete!()

    assert count_webhook_jobs(delivery_id) == 0
    assert {:ok, :duplicate} = WebhookReceipt.accept(headers, body)
    assert count_webhook_jobs(delivery_id) == 0
  end

  test "invalid signatures, unknown installations, and unsupported events have no receipt effects" do
    context = installation_context("rejected")

    invalid_delivery = "delivery-invalid-#{Ecto.UUID.generate()}"
    valid_body = payload(context.external_installation_id)

    invalid_headers = %{
      "x-github-delivery" => invalid_delivery,
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => "sha256=invalid"
    }

    assert {:error, :invalid_signature} = WebhookReceipt.accept(invalid_headers, valid_body)
    assert no_receipt_effects?(invalid_delivery)

    unknown_delivery = "delivery-unknown-#{Ecto.UUID.generate()}"
    unknown_body = payload(System.unique_integer([:positive]))

    assert {:error, :invalid_signature} =
             WebhookReceipt.accept(
               signed_headers(
                 unknown_delivery,
                 "pull_request",
                 unknown_body,
                 context.webhook_secret
               ),
               unknown_body
             )

    assert no_receipt_effects?(unknown_delivery)

    unsupported_delivery = "delivery-unsupported-#{Ecto.UUID.generate()}"

    assert {:error, :unsupported_event} =
             WebhookReceipt.accept(
               signed_headers(
                 unsupported_delivery,
                 "push",
                 valid_body,
                 context.webhook_secret
               ),
               valid_body
             )

    assert no_receipt_effects?(unsupported_delivery)
  end

  test "events without an implemented authoritative reconciliation path are rejected" do
    context = installation_context("unsupported-installation-event")
    delivery_id = "delivery-installation-#{Ecto.UUID.generate()}"

    body =
      Jason.encode!(%{
        "action" => "created",
        "installation" => %{"id" => context.external_installation_id}
      })

    headers = signed_headers(delivery_id, "installation", body, context.webhook_secret)

    assert {:error, :unsupported_event} = WebhookReceipt.accept(headers, body)
    assert no_receipt_effects?(delivery_id)
  end

  test "secret-store outages return a retryable service failure without receipt effects" do
    context = installation_context("secret-unavailable")
    delivery_id = "delivery-secret-unavailable-#{Ecto.UUID.generate()}"
    body = payload(context.external_installation_id)
    headers = signed_headers(delivery_id, "pull_request", body, context.webhook_secret)

    configured = Application.fetch_env!(:office_graph, :github_secret_store)
    Application.put_env(:office_graph, :github_secret_store, UnavailableSecretStore)
    on_exit(fn -> Application.put_env(:office_graph, :github_secret_store, configured) end)

    assert {:error, :receipt_unavailable} = WebhookReceipt.accept(headers, body)
    assert no_receipt_effects?(delivery_id)
  end

  defp installation_context(label) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    external_installation_id = System.unique_integer([:positive])
    webhook_reference = "test-secret://github/#{label}/webhook"
    webhook_secret = "webhook-secret-#{label}"

    assert {:ok, bound} =
             GitHubIntegration.bind_installation(bootstrap.session, %{
               idempotency_key: "bind-webhook-#{label}",
               external_installation_id: external_installation_id,
               workspace_id: nil,
               app_slug: "office-graph",
               account_login: "Un3qual",
               account_type: "organization",
               service_principal_email: "github-service-webhook-#{label}@office-graph.local",
               webhook_principal_email: "github-webhook-#{label}@office-graph.local",
               webhook_secret_reference: webhook_reference,
               app_private_key_reference: "test-secret://github/#{label}/private-key",
               permissions: [%{name: "pull_requests", access_level: "write"}]
             })

    TestAdapter.put(%{webhook_reference => webhook_secret})

    %{
      external_installation_id: external_installation_id,
      organization_id: bootstrap.organization.id,
      installation_id: bound.installation.id,
      webhook_secret: webhook_secret
    }
  end

  defp payload(external_installation_id) do
    Jason.encode!(%{
      "action" => "opened",
      "installation" => %{"id" => external_installation_id},
      "pull_request" => %{"id" => 44}
    })
  end

  defp signed_headers(delivery_id, event, body, secret) do
    signature = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

    %{
      "x-github-delivery" => delivery_id,
      "x-github-event" => event,
      "x-hub-signature-256" => "sha256=#{signature}"
    }
  end

  defp no_receipt_effects?(delivery_id) do
    count_archives(delivery_id) == 0 and count_operations(delivery_id) == 0 and
      count_events(delivery_id) == 0 and count_webhook_jobs(delivery_id) == 0
  end

  defp count_archives(delivery_id) do
    RawArchive
    |> Ash.Query.filter(external_delivery_id == ^delivery_id)
    |> Ash.count!(authorize?: false)
  end

  defp count_operations(delivery_id) do
    OperationCorrelation
    |> Ash.Query.filter(
      operation_kind == "system" and idempotency_scope == "github:delivery" and
        idempotency_key == ^delivery_id
    )
    |> Ash.count!(authorize?: false)
  end

  defp count_events(delivery_id) do
    event_identity = "github-delivery:#{delivery_id}"

    DomainEvent
    |> Ash.Query.filter(event_key == ^event_identity)
    |> Ash.count!(authorize?: false)
  end

  defp count_webhook_jobs(delivery_id) do
    worker = inspect(WebhookWorker)

    Oban.Job
    |> where(
      [job],
      job.worker == ^worker and fragment("?->>'delivery_id'", job.args) == ^delivery_id
    )
    |> Repo.aggregate(:count)
  end
end
