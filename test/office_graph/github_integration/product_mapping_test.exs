defmodule OfficeGraph.GitHubIntegration.ProductMappingTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration, Operations, Repo, WorkGraph}
  alias OfficeGraph.ExternalRefs.ExternalReference

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Reconciler,
    ReconciliationRequest
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.GitHubIntegration.SecretStore.TestAdapter, as: SecretStore
  alias OfficeGraph.SoftwareProving.ReviewComment
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

  test "check signals close when healthy and reopen on a later failure" do
    context = context("check-signal-lifecycle")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-check-signal-lifecycle"
      })

    failing = %{mapping_snapshot() | review_comments: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, failing}})

    assert {:ok, first_outcome} =
             Reconciler.reconcile(operation!(context, request, "failing"), request)

    assert [signal_id] = first_outcome.signal_ids
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "open"

    [failed_check] = failing.check_runs

    healthy = %{
      failing
      | provider_version: "v4",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z],
        check_runs: [%{failed_check | conclusion: "success"}]
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, healthy}})

    assert {:ok, healthy_outcome} =
             Reconciler.reconcile(operation!(context, request, "healthy"), request)

    assert healthy_outcome.signal_ids == []
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "closed"

    failing_again = %{
      failing
      | provider_version: "v5",
        provider_sequence: 5,
        provider_updated_at: ~U[2026-07-14 13:02:00Z]
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, failing_again}})

    assert {:ok, repeated_outcome} =
             Reconciler.reconcile(operation!(context, request, "failing-again"), request)

    assert repeated_outcome.signal_ids == [signal_id]
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "open"
    assert Repo.aggregate(Signal, :count) == 1
  end

  test "non-published review comments do not create or retain open signals" do
    context = context("comment-signal-lifecycle")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-comment-signal-lifecycle"
      })

    published = %{mapping_snapshot() | check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, published}})

    assert {:ok, first_outcome} =
             Reconciler.reconcile(operation!(context, request, "published"), request)

    assert [signal_id] = first_outcome.signal_ids
    [published_comment] = published.review_comments

    deleted = %{
      published
      | provider_version: "v4",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z],
        review_comments: [%{published_comment | state: "deleted", body: ""}]
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, deleted}})

    assert {:ok, deleted_outcome} =
             Reconciler.reconcile(operation!(context, request, "deleted"), request)

    assert deleted_outcome.signal_ids == []
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "closed"

    pending_context = context("pending-comment")

    pending_request =
      ReconciliationRequest.new!(%{
        installation_id: pending_context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-pending-comment"
      })

    pending = %{
      published
      | review_comments: [%{published_comment | state: "pending"}]
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, pending}})

    assert {:ok, pending_outcome} =
             Reconciler.reconcile(
               operation!(pending_context, pending_request, "pending"),
               pending_request
             )

    assert pending_outcome.signal_ids == []
    assert Repo.aggregate(Signal, :count) == 1
  end

  test "organization-scoped reconciliation skips workspace-only signal creation" do
    context = context("organization-scoped", nil)

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-organization-scoped"
      })

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, mapping_snapshot()}})
    operation = operation!(context, request, "organization-scoped")
    signal_count = Repo.aggregate(Signal, :count)

    assert {:ok, outcome} = Reconciler.reconcile(operation, request)
    assert outcome.state == "reconciled"
    assert outcome.signal_ids == []
    assert Repo.aggregate(Signal, :count) == signal_count
  end

  test "reconciliation preserves review comment parent relationships" do
    context = context("comment-parent")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-comment-parent"
      })

    parent = %Adapter.ReviewCommentSnapshot{
      node_id: "PRRC_parent",
      database_id: 501,
      review_thread_node_id: "PRRT_mapping",
      body: "Parent review comment",
      author_label: "reviewer",
      state: "published",
      published_at: ~U[2026-07-14 12:57:00Z]
    }

    reply = %Adapter.ReviewCommentSnapshot{
      node_id: "PRRC_reply",
      database_id: 502,
      review_thread_node_id: "PRRT_mapping",
      parent_comment_node_id: "PRRC_parent",
      body: "Reply review comment",
      author_label: "author",
      state: "published",
      published_at: ~U[2026-07-14 12:58:00Z]
    }

    snapshot = %{mapping_snapshot() | review_comments: [reply, parent], check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, snapshot}})

    assert {:ok, _outcome} = Reconciler.reconcile(operation!(context, request), request)

    persisted_parent =
      ReviewComment
      |> Ash.Query.filter(body == "Parent review comment")
      |> Ash.read_one!(authorize?: false)

    persisted_reply =
      ReviewComment
      |> Ash.Query.filter(body == "Reply review comment")
      |> Ash.read_one!(authorize?: false)

    assert persisted_reply.parent_comment_id == persisted_parent.id
  end

  test "concurrent signal mapping reuses the persisted graph item and signal" do
    context = context("signal-concurrency")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-signal-concurrency"
      })

    snapshot = %{mapping_snapshot() | review_comments: [], check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, snapshot}})

    assert {:ok, _outcome} =
             Reconciler.reconcile(operation!(context, request, "seed-reference"), request)

    reference =
      ExternalReference
      |> Ash.Query.filter(object_type == "repository")
      |> Ash.read_one!(authorize?: false)

    operations =
      for suffix <- 1..10 do
        operation!(context, request, suffix)
      end

    signal_count = Repo.aggregate(Signal, :count)

    results =
      operations
      |> Enum.map(fn operation ->
        Task.async(fn ->
          WorkGraph.ensure_integration_signal(operation, reference, %{
            title: "Shared provider signal",
            body: "One signal must own this provider reference."
          })
        end)
      end)
      |> Task.await_many(10_000)

    assert Enum.all?(results, &match?({:ok, _result}, &1))

    signal_ids = Enum.map(results, fn {:ok, result} -> result.signal.id end)
    assert signal_ids |> Enum.uniq() |> length() == 1
    assert Repo.aggregate(Signal, :count) == signal_count + 1
  end

  defp context(label, workspace_id \\ :session_workspace) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    workspace_id =
      if workspace_id == :session_workspace, do: bootstrap.workspace.id, else: workspace_id

    private_key_reference = "test-secret://github/#{label}/private-key"

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-product-mapping-#{label}",
        external_installation_id: System.unique_integer([:positive]),
        workspace_id: workspace_id,
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

  defp operation!(context, request, suffix \\ "v3") do
    {:ok, system_request} =
      Operations.new_system_operation_request(%{
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.installation.workspace_id,
        principal_id: context.installation.service_principal_id,
        action: :integration_reconcile,
        authority_basis: "github_installation:#{context.installation.id}",
        causation_key: "github_delivery:#{request.delivery_id}",
        idempotency_scope: "github:object",
        idempotency_key: "mapping:#{request.object_id}:#{suffix}",
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
