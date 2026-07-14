defmodule OfficeGraph.GitHubIntegration.ReconciliationConcurrencyTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration, Operations, Repo}
  alias OfficeGraph.GitHubIntegration.{Adapter, Reconciler, ReconciliationRequest}
  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.GitHubIntegration.SecretStore.TestAdapter, as: SecretStore
  alias OfficeGraph.SoftwareProving.PullRequest

  test "concurrent reconciliation produces one canonical provider object" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    private_key_reference = "test-secret://github/concurrency/private-key"

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-reconciliation-concurrency",
        external_installation_id: System.unique_integer([:positive]),
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-concurrency@office-graph.local",
        webhook_principal_email: "github-webhook-concurrency@office-graph.local",
        webhook_secret_reference: "test-secret://github/concurrency/webhook",
        app_private_key_reference: private_key_reference,
        permissions: [%{name: "pull_requests", access_level: "write"}]
      })

    SecretStore.put(%{private_key_reference => "private-key-concurrency"})

    credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))

    request =
      ReconciliationRequest.new!(%{
        installation_id: bound.installation.id,
        object_type: "pull_request",
        object_id: "PR_concurrent",
        delivery_id: "delivery-concurrent"
      })

    snapshot = %Adapter.ReconciliationSnapshot{
      provider_version: "v1",
      provider_sequence: 1,
      provider_updated_at: ~U[2026-07-14 14:00:00Z],
      repository: %Adapter.RepositorySnapshot{
        node_id: "R_concurrent",
        database_id: 501,
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        owner_login: "Un3qual",
        visibility: "private"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: "PR_concurrent",
        database_id: 502,
        number: 24,
        title: "Concurrent reconciliation",
        state: "open",
        is_draft: false
      },
      review_threads: [],
      review_comments: [],
      check_runs: []
    }

    Provider.put(%{{"pull_request", "PR_concurrent"} => {:ok, snapshot}})

    operations =
      for suffix <- 1..2 do
        {:ok, system_request} =
          Operations.new_system_operation_request(%{
            organization_id: bootstrap.organization.id,
            workspace_id: bootstrap.workspace.id,
            principal_id: bound.installation.service_principal_id,
            action: :integration_reconcile,
            authority_basis: "github_installation:#{bound.installation.id}",
            causation_key: "github_delivery:delivery-concurrent-#{suffix}",
            idempotency_scope: "github:object",
            idempotency_key: "pull_request:PR_concurrent:v1:#{suffix}",
            credential_id: credential.credential_id
          })

        {:ok, operation} = Operations.start_system_operation(system_request)
        operation
      end

    results =
      operations
      |> Enum.map(&Task.async(fn -> Reconciler.reconcile(&1, request) end))
      |> Task.await_many(10_000)

    assert Enum.all?(results, &match?({:ok, _outcome}, &1))
    assert Repo.aggregate(PullRequest, :count) == 1
  end
end
