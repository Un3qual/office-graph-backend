defmodule OfficeGraph.GitHubIntegration.ReconciliationConcurrencyTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration, Operations, Repo}
  alias OfficeGraph.GitHubIntegration.{Adapter, Reconciler, ReconciliationRequest}
  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.GitHubIntegration.SecretStore.TestAdapter, as: SecretStore
  alias OfficeGraph.SoftwareProving.PullRequest

  test "distinct webhook objects for one pull request produce one canonical provider object" do
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
      review_comments: [
        %Adapter.ReviewCommentSnapshot{
          node_id: "PRRC_concurrent",
          database_id: 503,
          body: "Concurrent review comment",
          state: "published"
        }
      ],
      check_runs: [
        %Adapter.CheckRunSnapshot{
          node_id: "CR_concurrent",
          database_id: 504,
          name: "Concurrent check",
          status: "completed",
          conclusion: "success"
        }
      ]
    }

    requests = [
      ReconciliationRequest.new!(%{
        installation_id: bound.installation.id,
        object_type: "review_comment",
        object_id: "PRRC_concurrent",
        delivery_id: "delivery-concurrent-review-comment"
      }),
      ReconciliationRequest.new!(%{
        installation_id: bound.installation.id,
        object_type: "check_run",
        object_id: "CR_concurrent",
        delivery_id: "delivery-concurrent-check-run"
      })
    ]

    Provider.put(%{
      {"review_comment", "PRRC_concurrent"} => {:ok, snapshot},
      {"check_run", "CR_concurrent"} => {:ok, snapshot}
    })

    operations =
      Enum.map(requests, fn request ->
        {:ok, system_request} =
          Operations.new_system_operation_request(%{
            organization_id: bootstrap.organization.id,
            workspace_id: bootstrap.workspace.id,
            principal_id: bound.installation.service_principal_id,
            action: :integration_reconcile,
            authority_basis: "github_installation:#{bound.installation.id}",
            causation_key: "github_delivery:#{request.delivery_id}",
            idempotency_scope: "github:object",
            idempotency_key: "#{request.object_type}:#{request.object_id}:v1",
            credential_id: credential.credential_id
          })

        {:ok, operation} = Operations.start_system_operation(system_request)
        {operation, request}
      end)

    results =
      operations
      |> Enum.map(fn {operation, request} ->
        Task.async(fn -> Reconciler.reconcile(operation, request) end)
      end)
      |> Task.await_many(10_000)

    assert Enum.all?(results, &match?({:ok, _outcome}, &1))
    assert Repo.aggregate(PullRequest, :count) == 1
  end
end
