defmodule OfficeGraph.GitHubIntegration.ReconciliationTest do
  use OfficeGraph.DataCase, async: false

  require Ash.Query

  alias OfficeGraph.{Foundation, GitHubIntegration, Operations, Repo}
  alias OfficeGraph.ExternalRefs.ExternalReference

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Reconciler,
    ReconciliationRequest,
    SecretStore.TestAdapter,
    SyncOutcome
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.SoftwareProving.{PullRequest, Repository}
  alias OfficeGraph.SoftwareProving.GitHub.RepositoryExtension

  defmodule UnavailableSecretStore do
    @behaviour OfficeGraph.GitHubIntegration.SecretStore

    @impl true
    def fetch(_reference, _scope), do: {:error, :unavailable}
  end

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
    reset_at = DateTime.add(DateTime.utc_now(), 120, :second)

    Provider.put(%{
      {"pull_request", "PR_node_failure"} => {:error, {:rate_limited, reset_at}}
    })

    assert {:error, {:retryable, :provider_rate_limited, ^reset_at}} =
             Reconciler.reconcile(rate_limited_operation, request)

    rate_limited_outcome =
      SyncOutcome
      |> Ash.Query.filter(operation_id == ^rate_limited_operation.id)
      |> Ash.read_one!(authorize?: false)

    assert rate_limited_outcome.retry_at == reset_at

    Provider.put(%{
      {"pull_request", "PR_node_failure"} =>
        {:ok, snapshot(1, "open", "PR_node_failure", "R_node_failure")}
    })

    assert {:ok, recovered} = Reconciler.reconcile(rate_limited_operation, request)
    assert recovered.state == "reconciled"

    network_operation = reconciliation_operation!(context, request, "network-unavailable")
    Provider.put(%{{"pull_request", "PR_node_failure"} => {:error, :network_error}})

    assert {:error, {:retryable, :provider_unavailable}} =
             Reconciler.reconcile(network_operation, request)

    network_outcome =
      SyncOutcome
      |> Ash.Query.filter(operation_id == ^network_operation.id)
      |> Ash.read_one!(authorize?: false)

    assert network_outcome.state == "retryable"
    assert network_outcome.failure_code == "provider_unavailable"

    Provider.put(%{
      {"pull_request", "PR_node_failure"} =>
        {:ok, snapshot(2, "open", "PR_node_failure", "R_node_failure")}
    })

    assert {:ok, network_recovered} = Reconciler.reconcile(network_operation, request)
    assert network_recovered.state == "reconciled"

    Provider.put(%{
      {"pull_request", "PR_node_failure"} => {:error, :installation_revoked}
    })

    revoked_operation = reconciliation_operation!(context, request, "revoked")

    assert {:error, {:terminal, :installation_revoked}} =
             Reconciler.reconcile(revoked_operation, request)
  end

  test "transient private-key resolution failures are persisted as retryable outcomes" do
    context = reconciliation_context("credential-unavailable")
    request = request(context, "pull_request", "PR_credential", "delivery-credential")
    operation = reconciliation_operation!(context, request, "credential-unavailable")

    configured = Application.fetch_env!(:office_graph, :github_secret_store)
    Application.put_env(:office_graph, :github_secret_store, UnavailableSecretStore)
    on_exit(fn -> Application.put_env(:office_graph, :github_secret_store, configured) end)

    assert {:error, {:retryable, :provider_unavailable}} =
             Reconciler.reconcile(operation, request)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(operation_id == ^operation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "retryable"
    assert outcome.failure_code == "provider_unavailable"
  end

  test "malformed nested snapshots fail as invalid provider responses before writes" do
    context = reconciliation_context("invalid-nested-snapshot")
    request = request(context, "pull_request", "PR_invalid_nested", "delivery-invalid-nested")
    operation = reconciliation_operation!(context, request, "invalid-nested")

    invalid_snapshot =
      snapshot(1, "open", "PR_invalid_nested", "R_invalid_nested")
      |> then(fn provider_snapshot ->
        %{provider_snapshot | repository: %{provider_snapshot.repository | name: nil}}
      end)

    Provider.put(%{{"pull_request", "PR_invalid_nested"} => {:ok, invalid_snapshot}})

    assert {:error, {:terminal, :invalid_provider_response}} =
             Reconciler.reconcile(operation, request)

    assert Repo.aggregate(Repository, :count) == 0
  end

  test "non-pull-request deliveries require the requested object in the snapshot" do
    context = reconciliation_context("requested-object")

    for {object_type, object_id} <- [
          {"review_comment", "PRRC_missing"},
          {"check_run", "CR_missing"}
        ] do
      request =
        request(
          context,
          object_type,
          object_id,
          "delivery-requested-object-#{object_type}"
        )

      operation = reconciliation_operation!(context, request, object_type)

      Provider.put(%{
        {object_type, object_id} =>
          {:ok, snapshot(1, "open", "PR_requested_object", "R_requested_object")}
      })

      assert {:error, {:terminal, :invalid_provider_response}} =
               Reconciler.reconcile(operation, request)
    end
  end

  test "shared GitHub node identities reconcile independently per organization" do
    suffix = System.unique_integer([:positive])

    first =
      reconciliation_context("tenant-a-#{suffix}",
        organization_name: "GitHub tenant A #{suffix}",
        organization_slug: "github-tenant-a-#{suffix}",
        workspace_name: "GitHub tenant A workspace #{suffix}",
        workspace_slug: "github-tenant-a-workspace-#{suffix}",
        initiative_name: "GitHub tenant A initiative #{suffix}",
        initiative_slug: "github-tenant-a-initiative-#{suffix}",
        owner_email: "github-tenant-a-#{suffix}@office-graph.local"
      )

    second =
      reconciliation_context("tenant-b-#{suffix}",
        organization_name: "GitHub tenant B #{suffix}",
        organization_slug: "github-tenant-b-#{suffix}",
        workspace_name: "GitHub tenant B workspace #{suffix}",
        workspace_slug: "github-tenant-b-workspace-#{suffix}",
        initiative_name: "GitHub tenant B initiative #{suffix}",
        initiative_slug: "github-tenant-b-initiative-#{suffix}",
        owner_email: "github-tenant-b-#{suffix}@office-graph.local"
      )

    provider_snapshot = snapshot(1, "open", "PR_shared", "R_shared")

    TestAdapter.put(%{
      first.private_key_reference => "private-key-tenant-a",
      second.private_key_reference => "private-key-tenant-b"
    })

    Provider.put(%{{"pull_request", "PR_shared"} => {:ok, provider_snapshot}})

    first_request = request(first, "pull_request", "PR_shared", "delivery-tenant-a")
    second_request = request(second, "pull_request", "PR_shared", "delivery-tenant-b")

    assert {:ok, _outcome} =
             Reconciler.reconcile(
               reconciliation_operation!(first, first_request, "shared"),
               first_request
             )

    assert {:ok, _outcome} =
             Reconciler.reconcile(
               reconciliation_operation!(second, second_request, "shared"),
               second_request
             )

    assert Repo.aggregate(Repository, :count) == 2
    assert Repo.aggregate(RepositoryExtension, :count) == 2

    references =
      ExternalReference
      |> Ash.Query.filter(external_id == "repository:R_shared")
      |> Ash.read!(authorize?: false)

    assert Enum.sort(Enum.map(references, & &1.organization_id)) ==
             Enum.sort([first.bootstrap.organization.id, second.bootstrap.organization.id])
  end

  test "shared GitHub node identities reconcile independently per workspace" do
    suffix = System.unique_integer([:positive])
    owner_email = "github-shared-workspace-#{suffix}@office-graph.local"

    first =
      reconciliation_context("workspace-a-#{suffix}",
        owner_email: owner_email,
        owner_name: "GitHub Shared Workspace Owner #{suffix}",
        workspace_name: "GitHub Shared Workspace A #{suffix}",
        workspace_slug: "github-shared-workspace-a-#{suffix}",
        initiative_name: "GitHub Shared Initiative A #{suffix}",
        initiative_slug: "github-shared-initiative-a-#{suffix}"
      )

    second =
      reconciliation_context("workspace-b-#{suffix}",
        owner_email: owner_email,
        owner_name: "GitHub Shared Workspace Owner #{suffix}",
        workspace_name: "GitHub Shared Workspace B #{suffix}",
        workspace_slug: "github-shared-workspace-b-#{suffix}",
        initiative_name: "GitHub Shared Initiative B #{suffix}",
        initiative_slug: "github-shared-initiative-b-#{suffix}"
      )

    assert first.bootstrap.organization.id == second.bootstrap.organization.id
    assert first.bootstrap.workspace.id != second.bootstrap.workspace.id

    TestAdapter.put(%{
      first.private_key_reference => "private-key-workspace-a",
      second.private_key_reference => "private-key-workspace-b"
    })

    provider_snapshot = snapshot(1, "open", "PR_workspace_shared", "R_workspace_shared")
    Provider.put(%{{"pull_request", "PR_workspace_shared"} => {:ok, provider_snapshot}})

    first_request =
      request(first, "pull_request", "PR_workspace_shared", "delivery-workspace-a")

    second_request =
      request(second, "pull_request", "PR_workspace_shared", "delivery-workspace-b")

    assert {:ok, _outcome} =
             Reconciler.reconcile(
               reconciliation_operation!(first, first_request, "shared"),
               first_request
             )

    assert {:ok, _outcome} =
             Reconciler.reconcile(
               reconciliation_operation!(second, second_request, "shared"),
               second_request
             )

    repositories =
      Repository
      |> Ash.Query.filter(provider_version == "v1")
      |> Ash.read!(authorize?: false)

    assert Enum.sort(Enum.map(repositories, & &1.workspace_id)) ==
             Enum.sort([first.bootstrap.workspace.id, second.bootstrap.workspace.id])

    assert Repo.aggregate(RepositoryExtension, :count) == 2

    references =
      ExternalReference
      |> Ash.Query.filter(external_id == "repository:R_workspace_shared")
      |> Ash.read!(authorize?: false)

    assert Enum.sort(Enum.map(references, & &1.workspace_id)) ==
             Enum.sort([first.bootstrap.workspace.id, second.bootstrap.workspace.id])
  end

  defp reconciliation_context(label, bootstrap_opts \\ []) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner(bootstrap_opts)
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
      credential_id: credential.credential_id,
      private_key_reference: private_key_reference
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

  defp snapshot(
         sequence,
         state,
         pull_request_node_id \\ "PR_node_44",
         repository_node_id \\ "R_node_office_graph"
       ) do
    %Adapter.ReconciliationSnapshot{
      provider_version: "v#{sequence}",
      provider_sequence: sequence,
      provider_updated_at: DateTime.add(~U[2026-07-14 12:00:00Z], sequence, :second),
      repository: %Adapter.RepositorySnapshot{
        node_id: repository_node_id,
        database_id: 101,
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        owner_login: "Un3qual",
        default_ref_name: "main",
        visibility: "private",
        url: "https://github.com/Un3qual/office-graph-backend"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: pull_request_node_id,
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
