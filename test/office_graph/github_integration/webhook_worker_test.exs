defmodule OfficeGraph.GitHubIntegration.WebhookWorkerTest do
  use OfficeGraph.DataCase, async: false

  import Ecto.Query

  alias OfficeGraph.{Foundation, GitHubIntegration, Repo}

  alias OfficeGraph.DurableDelivery.DomainEvent
  alias OfficeGraph.Integrations.RawArchive

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Installation,
    InstallationCredential,
    RecordLoaderTestAdapter,
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

  test "deleted review-comment deliveries reconcile through the surviving pull request" do
    context = worker_context("deleted-review-comment")
    pull_request_node_id = "PR_worker_deleted_review_comment"

    body =
      Jason.encode!(%{
        "action" => "deleted",
        "installation" => %{"id" => context.external_installation_id},
        "comment" => %{"node_id" => "PRRC_worker_deleted"},
        "pull_request" => %{"node_id" => pull_request_node_id, "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-deleted-review-comment",
      "x-github-event" => "pull_request_review_comment",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    provider_snapshot =
      snapshot()
      |> then(fn value ->
        %{value | pull_request: %{value.pull_request | node_id: pull_request_node_id}}
      end)

    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, provider_snapshot}})

    assert :ok = WebhookWorker.perform(webhook_job("delivery-worker-deleted-review-comment"))

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^context.installation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.object_type == "pull_request"
    assert outcome.object_id == pull_request_node_id
  end

  test "transient installation lookup failures retry without terminal metadata" do
    context = worker_context("installation-lookup-unavailable")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_lookup_unavailable", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-lookup-unavailable",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)
    job = webhook_job("delivery-worker-lookup-unavailable")

    RecordLoaderTestAdapter.configure!(%{Installation => {:error, :database_unavailable}})

    assert {:error, "integration_storage_unavailable"} = WebhookWorker.perform(job)

    refute Map.has_key?(
             Repo.get!(Oban.Job, job.id).meta,
             "terminal_failure_code"
           )
  end

  test "exhausted pre-operation storage failures terminalize durably before cancellation" do
    context = worker_context("pre-operation-storage-exhausted")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_pre_operation_exhausted", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-pre-operation-exhausted",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)
    job = webhook_job("delivery-worker-pre-operation-exhausted")

    RecordLoaderTestAdapter.configure!(%{Installation => {:error, :database_unavailable}})

    Repo.query!("""
    ALTER TABLE github_sync_outcomes
    ADD CONSTRAINT test_github_pre_operation_terminalization_retry
    CHECK (state <> 'terminal')
    """)

    try do
      assert {:snooze, 5} = WebhookWorker.perform(%{job | attempt: 10, max_attempts: 10})

      staged_job = Repo.get!(Oban.Job, job.id)

      assert staged_job.meta["terminal_phase"] == "pre_operation"
      assert staged_job.meta["terminal_failure_code"] == "integration_storage_unavailable"
      assert staged_job.meta["terminal_installation_id"] == context.installation.id
      assert staged_job.meta["terminal_delivery_id"] == "delivery-worker-pre-operation-exhausted"
    after
      Repo.query!(
        "ALTER TABLE github_sync_outcomes DROP CONSTRAINT test_github_pre_operation_terminalization_retry"
      )
    end

    staged_job = Repo.get!(Oban.Job, job.id)
    assert {:cancel, "attempts_exhausted"} = WebhookWorker.perform(staged_job)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(
        installation_id == ^context.installation.id and object_type == "provider_delivery"
      )
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "terminal"
    assert outcome.object_id == "delivery-worker-pre-operation-exhausted"
    assert outcome.failure_class == "terminal"
    assert outcome.failure_code == "integration_storage_unavailable"

    RecordLoaderTestAdapter.put(%{})

    assert {:ok, health} =
             GitHubIntegration.integration_health(context.session, context.installation.id)

    assert health.terminal_count == 1
    assert Enum.any?(health.recent_failures, &(&1.code == "integration_storage_unavailable"))

    event = Ash.get!(DomainEvent, job.args["event_id"], authorize?: false)
    assert event.delivery_state == "failed"
    assert event.failure_code == "integration_storage_unavailable"
  end

  test "transient credential binding lookup failures remain retryable" do
    context = worker_context("credential-lookup-unavailable")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-credential-lookup-unavailable",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)
    Provider.put(%{{"pull_request", "PR_worker"} => {:ok, snapshot()}})
    job = webhook_job("delivery-worker-credential-lookup-unavailable")

    RecordLoaderTestAdapter.configure!(%{
      InstallationCredential => {:error, :database_unavailable}
    })

    assert {:error, "integration_storage_unavailable"} = WebhookWorker.perform(job)

    refute Map.has_key?(Repo.get!(Oban.Job, job.id).meta, "terminal_failure_code")
  end

  test "transient archive lookup failures remain retryable" do
    context = worker_context("archive-lookup-unavailable")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_archive_unavailable", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-archive-unavailable",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)
    job = webhook_job("delivery-worker-archive-unavailable")

    RecordLoaderTestAdapter.configure!(%{RawArchive => {:error, :database_unavailable}})

    assert {:error, "integration_storage_unavailable"} = WebhookWorker.perform(job)
    refute Map.has_key?(Repo.get!(Oban.Job, job.id).meta, "terminal_failure_code")
  end

  test "system-operation storage failures remain retryable before reconciliation" do
    context = worker_context("operation-storage-unavailable")

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => "delivery-worker-operation-storage-unavailable",
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)
    Provider.put(%{{"pull_request", "PR_worker"} => {:ok, snapshot()}})
    job = webhook_job("delivery-worker-operation-storage-unavailable")

    Repo.query!("""
    ALTER TABLE operation_correlations
    ADD CONSTRAINT test_github_operation_storage_unavailable
    CHECK (action <> 'integration.reconcile')
    """)

    result =
      try do
        WebhookWorker.perform(job)
      after
        Repo.query!(
          "ALTER TABLE operation_correlations DROP CONSTRAINT test_github_operation_storage_unavailable"
        )
      end

    assert {:error, "integration_storage_unavailable"} = result
    refute Map.has_key?(Repo.get!(Oban.Job, job.id).meta, "terminal_failure_code")
    assert Repo.aggregate(SyncOutcome, :count) == 0

    assert :ok = WebhookWorker.perform(job)
  end

  test "transient sync-outcome lookup failures remain retryable" do
    context = worker_context("outcome-lookup-unavailable")
    delivery_id = "delivery-worker-outcome-lookup-unavailable"
    pull_request_node_id = "PR_worker_outcome_lookup_unavailable"

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => pull_request_node_id, "number" => 25}
      })

    headers = %{
      "x-github-delivery" => delivery_id,
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    provider_snapshot =
      snapshot()
      |> then(fn value ->
        %{value | pull_request: %{value.pull_request | node_id: pull_request_node_id}}
      end)

    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, provider_snapshot}})
    job = webhook_job(delivery_id)

    RecordLoaderTestAdapter.configure!(%{SyncOutcome => {:error, :database_unavailable}})

    assert {:error, "integration_storage_unavailable"} = WebhookWorker.perform(job)
    refute Map.has_key?(Repo.get!(Oban.Job, job.id).meta, "terminal_failure_code")
    assert Repo.aggregate(SyncOutcome, :count) == 0

    RecordLoaderTestAdapter.put(%{})

    assert :ok = WebhookWorker.perform(job)
    assert Repo.aggregate(SyncOutcome, :count) == 1
  end

  test "exhausted sync-outcome lookup failures terminalize after storage recovers" do
    context = worker_context("outcome-lookup-exhausted")
    delivery_id = "delivery-worker-outcome-lookup-exhausted"

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{"node_id" => "PR_worker_outcome_lookup_exhausted", "number" => 25}
      })

    headers = %{
      "x-github-delivery" => delivery_id,
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)
    job = webhook_job(delivery_id)

    RecordLoaderTestAdapter.configure!(%{SyncOutcome => {:error, :database_unavailable}})

    assert {:snooze, 5} =
             WebhookWorker.perform(%{job | attempt: 10, max_attempts: 10})

    staged_job = Repo.get!(Oban.Job, job.id)

    assert staged_job.meta["terminal_failure_code"] == "integration_storage_unavailable"
    assert is_binary(staged_job.meta["terminal_operation_id"])
    assert Repo.aggregate(SyncOutcome, :count) == 0

    RecordLoaderTestAdapter.put(%{})

    assert {:cancel, "attempts_exhausted"} = WebhookWorker.perform(staged_job)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(
        installation_id == ^context.installation.id and delivery_id == ^delivery_id
      )
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "terminal"
    assert outcome.failure_class == "terminal"
    assert outcome.failure_code == "integration_storage_unavailable"
    assert outcome.object_type == "pull_request"
    assert outcome.object_id == "PR_worker_outcome_lookup_exhausted"
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

  test "exhausted reconciliation terminalizes the latest retry classification" do
    context = worker_context("retry-classification-change")
    delivery_id = "delivery-worker-retry-classification-change"

    body =
      Jason.encode!(%{
        "action" => "opened",
        "installation" => %{"id" => context.external_installation_id},
        "pull_request" => %{
          "node_id" => "PR_worker_retry_classification_change",
          "number" => 25
        }
      })

    headers = %{
      "x-github-delivery" => delivery_id,
      "x-github-event" => "pull_request",
      "x-hub-signature-256" => signature(body, context.webhook_secret)
    }

    assert {:ok, :accepted} = WebhookReceipt.accept(headers, body)

    Provider.put(%{
      {"pull_request", "PR_worker_retry_classification_change"} => {:error, :network_error}
    })

    job = webhook_job(delivery_id)
    assert {:error, "provider_unavailable"} = WebhookWorker.perform(job)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(installation_id == ^context.installation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "retryable"
    assert outcome.failure_code == "provider_unavailable"

    RecordLoaderTestAdapter.configure!(%{SyncOutcome => {:error, :database_unavailable}})

    assert {:snooze, 5} =
             WebhookWorker.perform(%{job | attempt: 10, max_attempts: 10})

    staged_job = Repo.get!(Oban.Job, job.id)
    assert staged_job.meta["terminal_failure_code"] == "integration_storage_unavailable"

    RecordLoaderTestAdapter.put(%{})

    assert {:cancel, "attempts_exhausted"} = WebhookWorker.perform(staged_job)

    outcome = Ash.get!(SyncOutcome, outcome.id, authorize?: false)
    assert outcome.state == "terminal"
    assert outcome.failure_class == "terminal"
    assert outcome.failure_code == "integration_storage_unavailable"
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
      session: bootstrap.session,
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
