defmodule OfficeGraph.GitHubIntegration.ReconciliationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration, Operations, Repo}

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Reconciler,
    ReconciliationRequest,
    SecretStore.TestAdapter,
    SyncOutcome
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.SoftwareProving.{PullRequest, Repository}

  test "newer provider versions win and stale or replayed snapshots do not overwrite truth" do
    context = reconciliation_context("ordering")
    request = request(context, "pull_request", "PR_node_44", "delivery-ordering")

    Provider.put(%{{"pull_request", "PR_node_44"} => {:ok, snapshot(2, "merged")}})
    operation_v2 = reconciliation_operation!(context, request, "v2")

    assert {:ok, reconciled} = Reconciler.reconcile(operation_v2, request)
    assert reconciled.state == "reconciled"

    Provider.put(%{{"pull_request", "PR_node_44"} => {:ok, snapshot(1, "open")}})
    operation_v1 = reconciliation_operation!(context, request, "v1")

    assert {:ok, stale} = Reconciler.reconcile(operation_v1, request)
    assert stale.state == "skipped_stale"

    assert {:ok, replayed} = Reconciler.reconcile(operation_v1, request)
    assert replayed.id == stale.id

    pull_request = Ash.get!(PullRequest, reconciled.resource_id, authorize?: false)
    assert pull_request.state == "merged"
    assert pull_request.provider_sequence == 2
    assert pull_request.provider_version == "v2"

    repository = Ash.get!(Repository, pull_request.repository_id, authorize?: false)
    assert repository.full_name == "Un3qual/office-graph-backend"

    assert Repo.aggregate(SyncOutcome, :count) == 2
  end

  test "rate limits and provider failures use stable retry or terminal classifications" do
    context = reconciliation_context("failures")
    request = request(context, "pull_request", "PR_node_failure", "delivery-failure")
    rate_limited_operation = reconciliation_operation!(context, request, "rate-limited")

    Provider.put(%{
      {"pull_request", "PR_node_failure"} => {:error, {:rate_limited, ~U[2026-07-14 20:00:00Z]}}
    })

    assert {:error, {:retryable, :provider_rate_limited}} =
             Reconciler.reconcile(rate_limited_operation, request)

    Provider.put(%{
      {"pull_request", "PR_node_failure"} => {:error, :installation_revoked}
    })

    revoked_operation = reconciliation_operation!(context, request, "revoked")

    assert {:error, {:terminal, :installation_revoked}} =
             Reconciler.reconcile(revoked_operation, request)
  end

  defp reconciliation_context(label) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    external_installation_id = System.unique_integer([:positive])
    private_key_reference = "test-secret://github/#{label}/private-key"

    assert {:ok, bound} =
             GitHubIntegration.bind_installation(bootstrap.session, %{
               idempotency_key: "bind-reconciliation-#{label}",
               external_installation_id: external_installation_id,
               workspace_id: bootstrap.workspace.id,
               app_slug: "office-graph",
               account_login: "Un3qual",
               account_type: "organization",
               service_principal_email: "github-service-reconcile-#{label}@office-graph.local",
               webhook_principal_email: "github-webhook-reconcile-#{label}@office-graph.local",
               webhook_secret_reference: "test-secret://github/#{label}/webhook",
               app_private_key_reference: private_key_reference,
               permissions: [
                 %{name: "checks", access_level: "write"},
                 %{name: "pull_requests", access_level: "write"}
               ]
             })

    TestAdapter.put(%{private_key_reference => "private-key-#{label}"})

    credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))

    %{
      bootstrap: bootstrap,
      installation: bound.installation,
      credential_id: credential.credential_id
    }
  end

  defp request(context, object_type, object_id, delivery_id) do
    ReconciliationRequest.new!(%{
      installation_id: context.installation.id,
      object_type: object_type,
      object_id: object_id,
      delivery_id: delivery_id
    })
  end

  defp reconciliation_operation!(context, request, suffix) do
    {:ok, system_request} =
      Operations.new_system_operation_request(%{
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.bootstrap.workspace.id,
        principal_id: context.installation.service_principal_id,
        action: :integration_reconcile,
        authority_basis: "github_installation:#{context.installation.id}",
        causation_key: "github_delivery:#{request.delivery_id}",
        idempotency_scope: "github:object",
        idempotency_key: "#{request.object_type}:#{request.object_id}:#{suffix}",
        credential_id: context.credential_id
      })

    {:ok, operation} = Operations.start_system_operation(system_request)
    operation
  end

  defp snapshot(sequence, state) do
    %Adapter.ReconciliationSnapshot{
      provider_version: "v#{sequence}",
      provider_sequence: sequence,
      provider_updated_at: DateTime.add(~U[2026-07-14 12:00:00Z], sequence, :second),
      repository: %Adapter.RepositorySnapshot{
        node_id: "R_node_office_graph",
        database_id: 101,
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        owner_login: "Un3qual",
        default_ref_name: "main",
        visibility: "private",
        url: "https://github.com/Un3qual/office-graph-backend"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: "PR_node_44",
        database_id: 44,
        number: 24,
        title: "Typed GitHub reconciliation",
        body: "Reconcile provider-neutral review state.",
        state: state,
        is_draft: false,
        author_label: "reviewer",
        url: "https://github.com/Un3qual/office-graph-backend/pull/24"
      },
      review_threads: [],
      review_comments: [],
      check_runs: []
    }
  end
end
