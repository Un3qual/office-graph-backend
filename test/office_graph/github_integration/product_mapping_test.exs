defmodule OfficeGraph.GitHubIntegration.ProductMappingTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration, Operations, Repo}

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Reconciler,
    ReconciliationRequest
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.GitHubIntegration.SecretStore.TestAdapter, as: SecretStore
  alias OfficeGraph.WorkGraph.{GraphRelationship, Signal}

  require Ash.Query

  test "review comments and failing checks become replay-safe signals with typed external links" do
    context = context("mapping")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-mapping"
      })

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, mapping_snapshot()}})
    operation = operation!(context, request)
    signal_count = Repo.aggregate(Signal, :count)

    assert {:ok, outcome} = Reconciler.reconcile(operation, request)
    assert outcome.state == "reconciled"
    assert length(outcome.signal_ids) == 2

    assert Repo.aggregate(Signal, :count) == signal_count + 2

    relationships =
      GraphRelationship
      |> Ash.Query.filter(operation_id == ^operation.id and lifecycle == "active")
      |> Ash.read!(authorize?: false)

    assert length(relationships) == 2
    assert Enum.all?(relationships, &(&1.asserting_principal_id == operation.principal_id))

    assert {:ok, replay} = Reconciler.reconcile(operation, request)
    assert replay.id == outcome.id
    assert Repo.aggregate(Signal, :count) == signal_count + 2
  end

  defp context(label) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    private_key_reference = "test-secret://github/#{label}/private-key"

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-product-mapping-#{label}",
        external_installation_id: System.unique_integer([:positive]),
        workspace_id: bootstrap.workspace.id,
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-mapping-#{label}@office-graph.local",
        webhook_principal_email: "github-webhook-mapping-#{label}@office-graph.local",
        webhook_secret_reference: "test-secret://github/#{label}/webhook",
        app_private_key_reference: private_key_reference,
        permissions: [
          %{name: "checks", access_level: "write"},
          %{name: "pull_requests", access_level: "write"}
        ]
      })

    SecretStore.put(%{private_key_reference => "private-key-#{label}"})

    credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))

    %{
      bootstrap: bootstrap,
      installation: bound.installation,
      credential_id: credential.credential_id
    }
  end

  defp operation!(context, request) do
    {:ok, system_request} =
      Operations.new_system_operation_request(%{
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.bootstrap.workspace.id,
        principal_id: context.installation.service_principal_id,
        action: :integration_reconcile,
        authority_basis: "github_installation:#{context.installation.id}",
        causation_key: "github_delivery:#{request.delivery_id}",
        idempotency_scope: "github:object",
        idempotency_key: "mapping:#{request.object_id}:v3",
        credential_id: context.credential_id
      })

    {:ok, operation} = Operations.start_system_operation(system_request)
    operation
  end

  defp mapping_snapshot do
    %Adapter.ReconciliationSnapshot{
      provider_version: "v3",
      provider_sequence: 3,
      provider_updated_at: ~U[2026-07-14 13:00:00Z],
      repository: %Adapter.RepositorySnapshot{
        node_id: "R_mapping",
        database_id: 201,
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        owner_login: "Un3qual",
        default_ref_name: "main",
        visibility: "private",
        url: "https://github.com/Un3qual/office-graph-backend"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: "PR_mapping_44",
        database_id: 244,
        number: 24,
        title: "Map review evidence",
        body: "Map review evidence into Office Graph.",
        state: "open",
        is_draft: false,
        author_label: "author",
        url: "https://github.com/Un3qual/office-graph-backend/pull/24"
      },
      review_threads: [
        %Adapter.ReviewThreadSnapshot{
          node_id: "PRRT_mapping",
          state: "open",
          path: "lib/example.ex",
          line: 42,
          side: "RIGHT"
        }
      ],
      review_comments: [
        %Adapter.ReviewCommentSnapshot{
          node_id: "PRRC_mapping",
          database_id: 301,
          review_thread_node_id: "PRRT_mapping",
          body: "Please handle the stale provider version.",
          author_label: "review-bot",
          state: "published",
          published_at: ~U[2026-07-14 12:58:00Z],
          url: "https://github.com/Un3qual/office-graph-backend/pull/24#discussion_r301"
        }
      ],
      check_runs: [
        %Adapter.CheckRunSnapshot{
          node_id: "CR_mapping",
          database_id: 401,
          name: "DeepSource",
          status: "completed",
          conclusion: "failure",
          details_url: "https://example.test/checks/401",
          completed_at: ~U[2026-07-14 12:59:00Z]
        }
      ]
    }
  end
end
