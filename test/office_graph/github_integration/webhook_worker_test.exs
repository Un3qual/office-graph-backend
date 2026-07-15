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

  test "review deliveries reconcile the pull request represented by the snapshot" do
    context = worker_context("review")

    body =
      Jason.encode!(%{
        "action" => "submitted",
        "installation" => %{"id" => context.external_installation_id},
        "review" => %{"node_id" => "PRR_worker_review"},
        "pull_request" => %{"node_id" => "PR_worker_review", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-review",
      "x-github-event" => "pull_request_review",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    provider_snapshot =
      snapshot()
      |> then(fn value ->
        %{value | pull_request: %{value.pull_request | node_id: "PR_worker_review"}}
      end)

    Provider.put(%{{"pull_request", "PR_worker_review"} => {:ok, provider_snapshot}})

    job = webhook_job("delivery-worker-review")
    assert :ok = WebhookWorker.perform(job)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^context.installation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.object_type == "pull_request"
    assert outcome.object_id == "PR_worker_review"
  end

  test "rate-limited reconciliation snoozes until the bounded provider reset" do
    context = worker_context("rate-limit")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_rate_limit", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-rate-limit",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    reset_at = DateTime.add(DateTime.utc_now(), 60, :second)

    Provider.put(%{
      {"pull_request", "PR_worker_rate_limit"} => {:error, {:rate_limited, reset_at}}
    })

    assert {:snooze, delay} = WebhookWorker.perform(webhook_job("delivery-worker-rate-limit"))
    assert delay in 1..60

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^context.installation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.retry_at == reset_at
  end

  test "terminal reconciliation failures persist their durable job reason" do
    context = worker_context("terminal-history")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_terminal_history", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-terminal-history",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    Provider.put(%{{"pull_request", "PR_worker_terminal_history"} => {:ok, %{}}})
    job = webhook_job("delivery-worker-terminal-history")

    assert {:cancel, "invalid_provider_response"} = WebhookWorker.perform(job)

    assert %{"terminal_failure_code" => "invalid_provider_response"} =
             Repo.get!(Oban.Job, job.id).meta
  end

  test "rate-limit snoozes cannot extend the fixed inbound attempt budget" do
    context = worker_context("rate-limit-exhausted")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_rate_limit_exhausted", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-rate-limit-exhausted",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    Provider.put(%{
      {"pull_request", "PR_worker_rate_limit_exhausted"} =>
        {:error, {:rate_limited, DateTime.add(DateTime.utc_now(), 60, :second)}}
    })

    job = webhook_job("delivery-worker-rate-limit-exhausted")
    snoozed_job = %{job | attempt: 10, max_attempts: 19}

    assert {:cancel, "attempts_exhausted"} = WebhookWorker.perform(snoozed_job)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^context.installation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "terminal"
    assert outcome.failure_class == "terminal"
    assert outcome.failure_code == "provider_rate_limited"
    assert outcome.retry_at == nil
  end

  test "exhausted transient reconciliation persists a terminal outcome" do
    context = worker_context("network-exhausted")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_network_exhausted", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-network-exhausted",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    Provider.put(%{
      {"pull_request", "PR_worker_network_exhausted"} => {:error, :network_error}
    })

    job = webhook_job("delivery-worker-network-exhausted")
    exhausted_job = %{job | attempt: 10, max_attempts: 10}

    assert {:cancel, "attempts_exhausted"} = WebhookWorker.perform(exhausted_job)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^context.installation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "terminal"
    assert outcome.failure_class == "terminal"
    assert outcome.failure_code == "provider_unavailable"
    assert outcome.retry_at == nil
  end

  test "exhausted reconciliation retains a terminalization-only retry phase" do
    context = worker_context("terminalization-retry")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_terminalization_retry", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-terminalization-retry",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    Provider.put(%{
      {"pull_request", "PR_worker_terminalization_retry"} => {:error, :network_error}
    })

    Repo.query!("""
    ALTER TABLE github_sync_outcomes
    ADD CONSTRAINT test_github_terminalization_retry
    CHECK (state <> 'terminal')
    """)

    job = webhook_job("delivery-worker-terminalization-retry")
    exhausted_job = %{job | attempt: 10, max_attempts: 10}

    assert {:snooze, 5} = WebhookWorker.perform(exhausted_job)

    terminalization_job = Repo.get!(Oban.Job, job.id)

    assert %{
             "terminal_failure_code" => "provider_unavailable",
             "terminal_operation_id" => operation_id
           } = terminalization_job.meta

    assert is_binary(operation_id)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^context.installation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "retryable"

    Repo.query!(
      "ALTER TABLE github_sync_outcomes DROP CONSTRAINT test_github_terminalization_retry"
    )

    terminalization_job = Repo.get!(Oban.Job, job.id)
    assert {:cancel, "attempts_exhausted"} = WebhookWorker.perform(terminalization_job)

    outcome = Ash.get!(SyncOutcome, outcome.id, authorize?: false)
    assert outcome.state == "terminal"
    assert outcome.failure_class == "terminal"
    assert outcome.failure_code == "provider_unavailable"
  end

  test "numeric webhook object ids match authoritative snapshot database ids" do
    context = worker_context("database-id")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"id" => 602, "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-database-id",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    Provider.put(%{{"pull_request", "602"} => {:ok, snapshot()}})

    assert :ok = WebhookWorker.perform(webhook_job("delivery-worker-database-id"))

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^context.installation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "reconciled"
    assert outcome.object_type == "pull_request"
    assert outcome.object_id == "602"
  end

  defp worker_context(label) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    external_installation_id = System.unique_integer([:positive])
    webhook_reference = "test-secret://github/worker/#{label}/webhook"
    private_key_reference = "test-secret://github/worker/#{label}/private-key"
    webhook_secret = "webhook-secret-worker-#{label}"

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-webhook-worker-#{label}",
        external_installation_id: external_installation_id,
        workspace_id: bootstrap.workspace.id,
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-worker-#{label}@office-graph.local",
        webhook_principal_email: "github-webhook-worker-#{label}@office-graph.local",
        webhook_secret_reference: webhook_reference,
        app_private_key_reference: private_key_reference,
        permissions: [%{name: "pull_requests", access_level: "write"}]
      })

    TestAdapter.put(%{
      webhook_reference => webhook_secret,
      private_key_reference => "private-key-worker-#{label}"
    })

    %{
      installation: bound.installation,
      external_installation_id: external_installation_id,
      webhook_secret: webhook_secret
    }
  end

  defp webhook_job(delivery_id) do
    worker_name = inspect(WebhookWorker)

    Repo.one!(
      from job in Oban.Job,
        where:
          job.worker == ^worker_name and
            fragment("?->>'delivery_id'", job.args) == ^delivery_id
    )
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
