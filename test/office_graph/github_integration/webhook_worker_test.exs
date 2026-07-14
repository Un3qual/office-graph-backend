defmodule OfficeGraph.GitHubIntegration.WebhookWorkerTest do
  use OfficeGraph.DataCase, async: false

  import Ecto.Query

  alias OfficeGraph.{Foundation, GitHubIntegration, Repo}

  alias OfficeGraph.DurableDelivery.DomainEvent

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    SecretStore.TestAdapter,
    SyncOutcome,
    WebhookReceipt,
    WebhookWorker
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider

  require Ash.Query

  test "verified partial deliveries reconcile through the durable worker and invalidate projections" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    external_installation_id = System.unique_integer([:positive])
    webhook_reference = "test-secret://github/worker/webhook"
    private_key_reference = "test-secret://github/worker/private-key"

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-webhook-worker",
        external_installation_id: external_installation_id,
        workspace_id: bootstrap.workspace.id,
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-worker@office-graph.local",
        webhook_principal_email: "github-webhook-worker@office-graph.local",
        webhook_secret_reference: webhook_reference,
        app_private_key_reference: private_key_reference,
        permissions: [%{name: "pull_requests", access_level: "write"}]
      })

    TestAdapter.put(%{
      webhook_reference => "webhook-secret-worker",
      private_key_reference => "private-key-worker"
    })

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker", "number" => 24}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, "webhook-secret-worker")
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    Provider.put(%{{"pull_request", "PR_worker"} => {:ok, snapshot()}})

    worker_name = inspect(WebhookWorker)
    job = Repo.one!(from job in Oban.Job, where: job.worker == ^worker_name)

    assert :ok = WebhookWorker.perform(job)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^bound.installation.id and state == "reconciled")
      |> Ash.read_one!(authorize?: false)

    assert outcome.object_id == "PR_worker"

    event =
      DomainEvent
      |> Ash.Query.filter(event_kind == "github.reconciliation.completed")
      |> Ash.read_one!(authorize?: false)

    assert event.subject_kind == "pull_request"
    assert event.subject_id == outcome.resource_id
  end

  defp snapshot do
    %Adapter.ReconciliationSnapshot{
      provider_version: "v1",
      provider_sequence: 1,
      provider_updated_at: ~U[2026-07-14 15:00:00Z],
      repository: %Adapter.RepositorySnapshot{
        node_id: "R_worker",
        database_id: 601,
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        owner_login: "Un3qual",
        default_ref_name: "main",
        visibility: "private",
        url: "https://github.com/Un3qual/office-graph-backend"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: "PR_worker",
        database_id: 602,
        number: 24,
        title: "Worker reconciliation",
        state: "open",
        is_draft: false,
        url: "https://github.com/Un3qual/office-graph-backend/pull/24"
      },
      review_threads: [],
      review_comments: [],
      check_runs: []
    }
  end

  defp signature(body, secret) do
    digest = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
    "sha256=#{digest}"
  end
end
