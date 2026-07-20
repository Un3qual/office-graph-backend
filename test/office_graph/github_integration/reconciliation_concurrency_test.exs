defmodule OfficeGraph.GitHubIntegration.ReconciliationConcurrencyTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{
    ExternalRefs,
    Foundation,
    GitHubIntegration,
    Integrations,
    Operations,
    Repo
  }

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Installation,
    Reconciler,
    ReconciliationRequest,
    SyncOutcome
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.GitHubIntegration.SecretStore.TestAdapter, as: SecretStore
  alias OfficeGraph.SoftwareProving.PullRequest

  require Ash.Query

  defmodule CoordinatedAdapter do
    @behaviour OfficeGraph.GitHubIntegration.Adapter

    @impl true
    def fetch(request) do
      owner = Application.fetch_env!(:office_graph, :github_coordinated_adapter_owner)
      send(owner, {:github_adapter_fetch, self(), request})

      receive do
        {:github_adapter_result, result} -> result
      after
        5_000 -> {:error, :provider_unavailable}
      end
    end

    @impl true
    def find_review_reply(_request, _credential), do: {:error, :adapter_unavailable}

    @impl true
    def reply_to_review(_request, _credential), do: {:error, :adapter_unavailable}

    @impl true
    def update_check(_request, _credential), do: {:error, :adapter_unavailable}
  end

  test "distinct webhook objects for one pull request produce one canonical provider object" do
    context = integration_context("provider-objects")
    bootstrap = context.bootstrap
    bound = context.bound
    credential = context.credential
    snapshot = snapshot()

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

  test "sync outcome writes serialize concurrent failures and failure-success races" do
    context = integration_context("sync-outcomes")
    configured = Application.fetch_env!(:office_graph, :github_adapter)
    Application.put_env(:office_graph, :github_adapter, CoordinatedAdapter)
    Application.put_env(:office_graph, :github_coordinated_adapter_owner, self())

    on_exit(fn ->
      Application.put_env(:office_graph, :github_adapter, configured)
      Application.delete_env(:office_graph, :github_coordinated_adapter_owner)
    end)

    failure_request =
      request(context, "pull_request", "PR_failure_race", "delivery-failure-race")

    failure_operation = operation!(context, failure_request, "failure-race")

    failure_tasks =
      for _index <- 1..2 do
        Task.async(fn -> Reconciler.reconcile(failure_operation, failure_request) end)
      end

    failure_fetchers = receive_fetchers(2)

    Enum.each(failure_fetchers, fn pid ->
      send(pid, {:github_adapter_result, {:error, :network_error}})
    end)

    failure_results = Task.await_many(failure_tasks, 10_000)

    assert Enum.all?(
             failure_results,
             &match?({:error, {:retryable, :provider_unavailable}}, &1)
           )

    assert outcome_count(failure_operation.id) == 1

    mixed_request = request(context, "pull_request", "PR_mixed_race", "delivery-mixed-race")
    mixed_operation = operation!(context, mixed_request, "mixed-race")

    mixed_tasks =
      for _index <- 1..2 do
        Task.async(fn -> Reconciler.reconcile(mixed_operation, mixed_request) end)
      end

    [failure_fetcher, success_fetcher] = receive_fetchers(2)
    send(failure_fetcher, {:github_adapter_result, {:error, :network_error}})

    send(
      success_fetcher,
      {:github_adapter_result,
       {:ok, snapshot("PR_mixed_race", "R_mixed_race", "PRRC_mixed", "CR_mixed")}}
    )

    mixed_results = Task.await_many(mixed_tasks, 10_000)

    assert Enum.any?(mixed_results, &match?({:ok, _outcome}, &1))

    assert Enum.all?(mixed_results, fn result ->
             match?({:ok, _outcome}, result) or
               match?({:error, {:retryable, :provider_unavailable}}, result)
           end)

    assert outcome_count(mixed_operation.id) == 1

    outcome =
      SyncOutcome
      |> Ash.Query.filter(operation_id == ^mixed_operation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "reconciled"
  end

  test "installation revocation applies only when its terminal outcome wins" do
    context = integration_context("revocation-race")
    configured = Application.fetch_env!(:office_graph, :github_adapter)
    Application.put_env(:office_graph, :github_adapter, CoordinatedAdapter)
    Application.put_env(:office_graph, :github_coordinated_adapter_owner, self())

    on_exit(fn ->
      Application.put_env(:office_graph, :github_adapter, configured)
      Application.delete_env(:office_graph, :github_coordinated_adapter_owner)
    end)

    request = request(context, "pull_request", "PR_revocation_race", "delivery-revocation-race")
    operation = operation!(context, request, "revocation-race")

    success_task = Task.async(fn -> Reconciler.reconcile(operation, request) end)
    revocation_task = Task.async(fn -> Reconciler.reconcile(operation, request) end)

    fetchers = receive_fetchers(2)
    assert success_task.pid in fetchers
    assert revocation_task.pid in fetchers

    send(
      success_task.pid,
      {:github_adapter_result,
       {:ok,
        snapshot("PR_revocation_race", "R_revocation_race", "PRRC_revocation", "CR_revocation")}}
    )

    assert {:ok, successful_outcome} = Task.await(success_task, 10_000)
    assert successful_outcome.state == "reconciled"

    send(revocation_task.pid, {:github_adapter_result, {:error, :installation_revoked}})

    assert {:ok, replayed_outcome} = Task.await(revocation_task, 10_000)
    assert replayed_outcome.id == successful_outcome.id

    installation = Ash.get!(Installation, context.bound.installation.id, authorize?: false)
    assert installation.lifecycle_state == "active"
  end

  test "provider reference creation is concurrency-safe for one scoped identity" do
    context = integration_context("external-reference-race")

    request =
      request(
        context,
        "pull_request",
        "PR_external_reference_race",
        "delivery-external-reference-race"
      )

    operation = operation!(context, request, "external-reference-race")
    {:ok, source} = Integrations.ensure_provider_source("github", "GitHub")

    attrs = %{
      provider: "github",
      object_type: "pull_request",
      external_id: "pull_request:PR_external_reference_race",
      url: "https://github.com/Un3qual/office-graph-backend/pull/25",
      resource_type: "pull_request",
      resource_id: Ecto.UUID.generate()
    }

    results =
      1..20
      |> Enum.map(fn _index ->
        Task.async(fn -> ExternalRefs.upsert_provider_reference(operation, source, attrs) end)
      end)
      |> Task.await_many(10_000)

    assert Enum.all?(results, &match?({:ok, _reference}, &1))

    reference_ids = Enum.map(results, fn {:ok, reference} -> reference.id end)
    assert reference_ids |> Enum.uniq() |> length() == 1
  end

  defp integration_context(label) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    private_key_reference = "test-secret://github/#{label}/private-key"

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-reconciliation-concurrency-#{label}",
        external_installation_id: System.unique_integer([:positive]),
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-concurrency-#{label}@office-graph.local",
        webhook_principal_email: "github-webhook-concurrency-#{label}@office-graph.local",
        webhook_secret_reference: "test-secret://github/#{label}/webhook",
        app_private_key_reference: private_key_reference,
        permissions: [%{name: "pull_requests", access_level: "write"}]
      })

    SecretStore.put(%{private_key_reference => "private-key-#{label}"})
    credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))

    %{bootstrap: bootstrap, bound: bound, credential: credential}
  end

  defp request(context, object_type, object_id, delivery_id) do
    ReconciliationRequest.new!(%{
      installation_id: context.bound.installation.id,
      object_type: object_type,
      object_id: object_id,
      delivery_id: delivery_id
    })
  end

  defp operation!(context, request, suffix) do
    {:ok, system_request} =
      Operations.new_system_operation_request(%{
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.bootstrap.workspace.id,
        principal_id: context.bound.installation.service_principal_id,
        action: :integration_reconcile,
        authority_basis: "github_installation:#{context.bound.installation.id}",
        causation_key: "github_delivery:#{request.delivery_id}",
        idempotency_scope: "github:object",
        idempotency_key: "#{request.object_type}:#{request.object_id}:#{suffix}",
        credential_id: context.credential.credential_id
      })

    {:ok, operation} = Operations.start_system_operation(system_request)
    operation
  end

  defp receive_fetchers(count) do
    for _index <- 1..count do
      receive do
        {:github_adapter_fetch, pid, _request} -> pid
      after
        5_000 -> flunk("timed out waiting for coordinated provider fetch")
      end
    end
  end

  defp outcome_count(operation_id) do
    SyncOutcome
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.count!(authorize?: false)
  end

  defp snapshot(
         pull_request_node_id \\ "PR_concurrent",
         repository_node_id \\ "R_concurrent",
         review_comment_node_id \\ "PRRC_concurrent",
         check_run_node_id \\ "CR_concurrent"
       ) do
    %Adapter.ReconciliationSnapshot{
      provider_version: "v1",
      provider_sequence: 1,
      provider_updated_at: ~U[2026-07-14 14:00:00Z],
      repository: %Adapter.RepositorySnapshot{
        node_id: repository_node_id,
        database_id: 501,
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        owner_login: "Un3qual",
        visibility: "private"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: pull_request_node_id,
        database_id: 502,
        number: 24,
        title: "Concurrent reconciliation",
        state: "open",
        is_draft: false
      },
      review_threads: [],
      review_comments: [
        %Adapter.ReviewCommentSnapshot{
          node_id: review_comment_node_id,
          database_id: 503,
          body: "Concurrent review comment",
          state: "published"
        }
      ],
      check_runs: [
        %Adapter.CheckRunSnapshot{
          node_id: check_run_node_id,
          database_id: 504,
          name: "Concurrent check",
          status: "completed",
          conclusion: "success"
        }
      ]
    }
  end
end
