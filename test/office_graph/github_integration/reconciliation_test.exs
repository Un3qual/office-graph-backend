defmodule OfficeGraph.GitHubIntegration.ReconciliationTest do
  use OfficeGraph.DataCase, async: false

  require Ash.Query

  alias OfficeGraph.{
    ExternalRefs,
    Foundation,
    GitHubIntegration,
    Integrations,
    Operations,
    Repo,
    SoftwareProving
  }

  alias OfficeGraph.ExternalRefs.ExternalReference

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Installation,
    InstallationCredential,
    RecordLoaderTestAdapter,
    Reconciler,
    ReconciliationRequest,
    SecretStore.TestAdapter,
    SyncOutcome
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.SoftwareProving.{CheckRun, PullRequest, Repository, ReviewComment}
  alias OfficeGraph.SoftwareProving.GitHub.RepositoryExtension

  defmodule UnavailableSecretStore do
    @behaviour OfficeGraph.GitHubIntegration.SecretStore

    @impl true
    def fetch(_reference, _scope), do: {:error, :unavailable}
  end

  test "newer provider versions win and stale or replayed snapshots do not overwrite truth" do
    context = reconciliation_context("ordering")
    request = request(context, "pull_request", "PR_node_44", "delivery-ordering")

    newer_snapshot =
      snapshot(2, "merged")
      |> then(fn value ->
        %{
          value
          | repository: %{
              value.repository
              | url: "https://github.com/Un3qual/office-graph-backend-new"
            },
            pull_request: %{
              value.pull_request
              | url: "https://github.com/Un3qual/office-graph-backend/pull/24-new"
            }
        }
      end)

    Provider.put(%{{"pull_request", "PR_node_44"} => {:ok, newer_snapshot}})
    operation_v2 = reconciliation_operation!(context, request, "v2")

    assert {:ok, reconciled} = Reconciler.reconcile(operation_v2, request)
    assert reconciled.state == "reconciled"

    older_snapshot =
      snapshot(1, "open")
      |> then(fn value ->
        %{
          value
          | repository: %{
              value.repository
              | url: "https://github.com/Un3qual/office-graph-backend-old"
            },
            pull_request: %{
              value.pull_request
              | url: "https://github.com/Un3qual/office-graph-backend/pull/24-old"
            }
        }
      end)

    Provider.put(%{{"pull_request", "PR_node_44"} => {:ok, older_snapshot}})
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

    repository_reference =
      ExternalReference
      |> Ash.Query.filter(external_id == "repository:R_node_office_graph")
      |> Ash.read_one!(authorize?: false)

    pull_request_reference =
      ExternalReference
      |> Ash.Query.filter(external_id == "pull_request:PR_node_44")
      |> Ash.read_one!(authorize?: false)

    assert repository_reference.url == "https://github.com/Un3qual/office-graph-backend-new"

    assert pull_request_reference.url ==
             "https://github.com/Un3qual/office-graph-backend/pull/24-new"

    assert Repo.aggregate(SyncOutcome, :count) == 2
  end

  test "stale nested resources do not refresh references or product work" do
    context = reconciliation_context("nested-ordering")
    pull_request_node_id = "PR_nested_ordering"
    repository_node_id = "R_nested_ordering"
    comment_node_id = "PRRC_nested_ordering"
    check_node_id = "CR_nested_ordering"
    request = request(context, "pull_request", pull_request_node_id, "delivery-nested-v1")
    operation_v1 = reconciliation_operation!(context, request, "nested-v1")

    initial_snapshot =
      snapshot(1, "open", pull_request_node_id, repository_node_id)
      |> Map.put(:review_comments, [
        %Adapter.ReviewCommentSnapshot{
          node_id: comment_node_id,
          database_id: 701,
          body: "Initial nested comment",
          author_label: "review-bot",
          state: "published",
          url: "https://example.test/comments/initial"
        }
      ])
      |> Map.put(:check_runs, [
        %Adapter.CheckRunSnapshot{
          node_id: check_node_id,
          database_id: 702,
          name: "Initial nested check",
          status: "completed",
          conclusion: "failure",
          details_url: "https://example.test/checks/initial"
        }
      ])

    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, initial_snapshot}})
    assert {:ok, _outcome} = Reconciler.reconcile(operation_v1, request)

    comment =
      ReviewComment
      |> Ash.Query.filter(body == "Initial nested comment")
      |> Ash.read_one!(authorize?: false)

    check =
      CheckRun
      |> Ash.Query.filter(name == "Initial nested check")
      |> Ash.read_one!(authorize?: false)

    comment =
      comment
      |> Ash.Changeset.for_update(:reconcile, %{
        body: "Authoritative nested comment",
        provider_version: "v3",
        provider_sequence: 3,
        operation_id: operation_v1.id
      })
      |> Repo.ash_update!()

    check =
      check
      |> Ash.Changeset.for_update(:reconcile, %{
        name: "Authoritative nested check",
        details_url: "https://example.test/checks/authoritative",
        provider_version: "v3",
        provider_sequence: 3,
        operation_id: operation_v1.id
      })
      |> Repo.ash_update!()

    {:ok, github_source} = Integrations.ensure_provider_source("github", "GitHub")

    assert {:ok, _reference} =
             ExternalRefs.upsert_provider_reference(operation_v1, github_source, %{
               provider: "github",
               object_type: "review_comment",
               external_id: "review_comment:#{comment_node_id}",
               url: "https://example.test/comments/authoritative",
               resource_type: "review_comment",
               resource_id: comment.id
             })

    assert {:ok, _reference} =
             ExternalRefs.upsert_provider_reference(operation_v1, github_source, %{
               provider: "github",
               object_type: "check_run",
               external_id: "check_run:#{check_node_id}",
               url: "https://example.test/checks/authoritative",
               resource_type: "check_run",
               resource_id: check.id
             })

    intermediate_snapshot =
      snapshot(2, "open", pull_request_node_id, repository_node_id)
      |> Map.put(:review_comments, [
        %Adapter.ReviewCommentSnapshot{
          node_id: comment_node_id,
          database_id: 701,
          body: "Stale nested comment",
          author_label: "review-bot",
          state: "published",
          url: "https://example.test/comments/stale"
        }
      ])
      |> Map.put(:check_runs, [
        %Adapter.CheckRunSnapshot{
          node_id: check_node_id,
          database_id: 702,
          name: "Stale nested check",
          status: "completed",
          conclusion: "failure",
          details_url: "https://example.test/checks/stale"
        }
      ])

    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, intermediate_snapshot}})
    operation_v2 = reconciliation_operation!(context, request, "nested-v2")

    assert {:ok, _outcome} = Reconciler.reconcile(operation_v2, request)

    comment_external_id = "review_comment:#{comment_node_id}"
    check_external_id = "check_run:#{check_node_id}"

    comment_reference =
      ExternalReference
      |> Ash.Query.filter(external_id == ^comment_external_id)
      |> Ash.read_one!(authorize?: false)

    check_reference =
      ExternalReference
      |> Ash.Query.filter(external_id == ^check_external_id)
      |> Ash.read_one!(authorize?: false)

    assert comment_reference.url == "https://example.test/comments/authoritative"
    assert check_reference.url == "https://example.test/checks/authoritative"
    assert Ash.get!(ReviewComment, comment.id, authorize?: false).body == comment.body
    assert Ash.get!(CheckRun, check.id, authorize?: false).name == check.name
  end

  test "newer provider reconciliation clears soft-delete tombstones" do
    context = reconciliation_context("resource-reactivation")
    pull_request_node_id = "PR_resource_reactivation"
    repository_node_id = "R_resource_reactivation"
    request = request(context, "pull_request", pull_request_node_id, "delivery-reactivation")
    operation_v1 = reconciliation_operation!(context, request, "reactivation-v1")
    first_snapshot = snapshot(1, "open", pull_request_node_id, repository_node_id)

    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, first_snapshot}})
    assert {:ok, _outcome} = Reconciler.reconcile(operation_v1, request)

    repository =
      Repository
      |> Ash.Query.filter(full_name == "Un3qual/office-graph-backend")
      |> Ash.read_one!(authorize?: false)

    deleted_at = ~U[2026-07-16 17:00:00Z]

    repository =
      repository
      |> Ash.Changeset.for_update(:reconcile, %{
        lifecycle_state: "deleted",
        deleted_at: deleted_at,
        operation_id: operation_v1.id
      })
      |> Repo.ash_update!()

    assert %DateTime{} = repository.deleted_at

    assert {:ok, nil} =
             Ash.get(Repository, repository.id, authorize?: false, not_found_error?: false)

    second_snapshot = snapshot(2, "open", pull_request_node_id, repository_node_id)
    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, second_snapshot}})

    assert {:ok, _outcome} =
             Reconciler.reconcile(
               reconciliation_operation!(context, request, "reactivation-v2"),
               request
             )

    reactivated = Ash.get!(Repository, repository.id, authorize?: false)
    assert reactivated.lifecycle_state == "active"
    assert is_nil(reactivated.deleted_at)
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

    installation = Ash.get!(Installation, context.installation.id, authorize?: false)
    assert installation.lifecycle_state == "revoked"
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

  test "transient installation and credential lookup failures persist retryable outcomes" do
    context = reconciliation_context("record-lookup-unavailable")
    RecordLoaderTestAdapter.configure!(%{})

    for {resource, label} <- [
          {Installation, "installation"},
          {InstallationCredential, "credential"}
        ] do
      request =
        request(
          context,
          "pull_request",
          "PR_#{label}_lookup_unavailable",
          "delivery-#{label}-lookup-unavailable"
        )

      operation = reconciliation_operation!(context, request, "#{label}-lookup-unavailable")

      RecordLoaderTestAdapter.put(%{resource => {:error, :database_unavailable}})

      assert {:error, {:retryable, :integration_storage_unavailable}} =
               Reconciler.reconcile(operation, request)

      outcome =
        SyncOutcome
        |> Ash.Query.filter(operation_id == ^operation.id)
        |> Ash.read_one!(authorize?: false)

      assert outcome.state == "retryable"
      assert outcome.failure_code == "integration_storage_unavailable"
    end
  end

  test "extension lookup outages remain retryable and recover without partial writes" do
    context = reconciliation_context("extension-lookup-unavailable")

    request =
      request(
        context,
        "pull_request",
        "PR_extension_lookup_unavailable",
        "delivery-extension-lookup-unavailable"
      )

    operation = reconciliation_operation!(context, request, "extension-lookup-unavailable")

    provider_snapshot =
      snapshot(
        1,
        "open",
        "PR_extension_lookup_unavailable",
        "R_extension_lookup_unavailable"
      )

    Provider.put(%{{"pull_request", request.object_id} => {:ok, provider_snapshot}})
    RecordLoaderTestAdapter.configure!(%{RepositoryExtension => {:error, :database_unavailable}})

    assert {:error, {:retryable, :integration_storage_unavailable}} =
             Reconciler.reconcile(operation, request)

    assert Repo.aggregate(Repository, :count) == 0

    RecordLoaderTestAdapter.put(%{})

    assert {:ok, recovered} = Reconciler.reconcile(operation, request)
    assert recovered.state == "reconciled"
    assert Repo.aggregate(Repository, :count) == 1
  end

  test "provider-neutral create failures remain retryable and recover atomically" do
    context = reconciliation_context("provider-resource-create-unavailable")

    request =
      request(
        context,
        "pull_request",
        "PR_provider_resource_create_unavailable",
        "delivery-provider-resource-create-unavailable"
      )

    operation =
      reconciliation_operation!(context, request, "provider-resource-create-unavailable")

    provider_snapshot =
      snapshot(
        1,
        "open",
        "PR_provider_resource_create_unavailable",
        "R_provider_resource_create_unavailable"
      )
      |> then(fn value ->
        %{value | repository: %{value.repository | name: "create-storage-blocked"}}
      end)

    Provider.put(%{{"pull_request", request.object_id} => {:ok, provider_snapshot}})
    repository_count = Repo.aggregate(Repository, :count)

    Repo.query!("""
    ALTER TABLE repositories
    ADD CONSTRAINT test_github_provider_resource_create_storage
    CHECK (name <> 'create-storage-blocked')
    """)

    result =
      try do
        Reconciler.reconcile(operation, request)
      after
        Repo.query!(
          "ALTER TABLE repositories DROP CONSTRAINT test_github_provider_resource_create_storage"
        )
      end

    assert {:error, {:retryable, :integration_storage_unavailable}} = result
    assert Repo.aggregate(Repository, :count) == repository_count

    assert {:ok, recovered} = Reconciler.reconcile(operation, request)
    assert recovered.state == "reconciled"

    pull_request = Ash.get!(PullRequest, recovered.resource_id, authorize?: false)
    repository = Ash.get!(Repository, pull_request.repository_id, authorize?: false)
    assert repository.name == "create-storage-blocked"
    assert repository.provider_sequence == 1
  end

  test "provider source write failures remain retryable and recover" do
    context = reconciliation_context("provider-source-write-unavailable")

    request =
      request(
        context,
        "pull_request",
        "PR_provider_source_write_unavailable",
        "delivery-provider-source-write-unavailable"
      )

    operation = reconciliation_operation!(context, request, "provider-source-write-unavailable")

    Provider.put(%{
      {"pull_request", request.object_id} =>
        {:ok,
         snapshot(
           1,
           "open",
           "PR_provider_source_write_unavailable",
           "R_provider_source_write_unavailable"
         )}
    })

    Repo.query!("""
    ALTER TABLE external_sources
    ADD CONSTRAINT test_github_reconciliation_provider_source_storage
    CHECK (NOT (kind = 'provider' AND key = 'github'))
    """)

    result =
      try do
        Reconciler.reconcile(operation, request)
      after
        Repo.query!(
          "ALTER TABLE external_sources DROP CONSTRAINT test_github_reconciliation_provider_source_storage"
        )
      end

    assert {:error, {:retryable, :integration_storage_unavailable}} = result
    assert Repo.aggregate(Repository, :count) == 0

    assert {:ok, recovered} = Reconciler.reconcile(operation, request)
    assert recovered.state == "reconciled"
  end

  test "external-reference write failures remain retryable and recover atomically" do
    context = reconciliation_context("external-reference-write-unavailable")
    pull_request_node_id = "PR_external_reference_write_unavailable"
    repository_node_id = "R_external_reference_write_unavailable"

    request =
      request(
        context,
        "pull_request",
        pull_request_node_id,
        "delivery-external-reference-write-unavailable"
      )

    operation =
      reconciliation_operation!(context, request, "external-reference-write-unavailable")

    Provider.put(%{
      {"pull_request", pull_request_node_id} =>
        {:ok, snapshot(1, "open", pull_request_node_id, repository_node_id)}
    })

    Repo.query!("""
    ALTER TABLE external_references
    ADD CONSTRAINT test_github_external_reference_storage
    CHECK (external_id <> 'repository:R_external_reference_write_unavailable')
    """)

    result =
      try do
        Reconciler.reconcile(operation, request)
      after
        Repo.query!(
          "ALTER TABLE external_references DROP CONSTRAINT test_github_external_reference_storage"
        )
      end

    assert {:error, {:retryable, :integration_storage_unavailable}} = result
    assert Repo.aggregate(Repository, :count) == 0

    assert {:ok, recovered} = Reconciler.reconcile(operation, request)
    assert recovered.state == "reconciled"
    assert Repo.aggregate(Repository, :count) == 1
  end

  test "provider-neutral update failures remain retryable and preserve canonical state" do
    context = reconciliation_context("provider-resource-update-unavailable")
    pull_request_node_id = "PR_provider_resource_update_unavailable"
    repository_node_id = "R_provider_resource_update_unavailable"

    initial_request =
      request(
        context,
        "pull_request",
        pull_request_node_id,
        "delivery-provider-resource-update-initial"
      )

    initial_snapshot =
      snapshot(1, "open", pull_request_node_id, repository_node_id)
      |> then(fn value ->
        %{value | repository: %{value.repository | name: "update-storage-initial"}}
      end)

    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, initial_snapshot}})

    assert {:ok, initial_outcome} =
             Reconciler.reconcile(
               reconciliation_operation!(context, initial_request, "provider-resource-update-v1"),
               initial_request
             )

    pull_request = Ash.get!(PullRequest, initial_outcome.resource_id, authorize?: false)
    repository = Ash.get!(Repository, pull_request.repository_id, authorize?: false)
    assert repository.name == "update-storage-initial"
    assert repository.provider_sequence == 1

    update_request =
      request(
        context,
        "pull_request",
        pull_request_node_id,
        "delivery-provider-resource-update-v2"
      )

    update_operation =
      reconciliation_operation!(context, update_request, "provider-resource-update-v2")

    updated_snapshot =
      snapshot(2, "open", pull_request_node_id, repository_node_id)
      |> then(fn value ->
        %{value | repository: %{value.repository | name: "update-storage-blocked"}}
      end)

    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, updated_snapshot}})

    Repo.query!("""
    ALTER TABLE repositories
    ADD CONSTRAINT test_github_provider_resource_update_storage
    CHECK (name <> 'update-storage-blocked')
    """)

    result =
      try do
        Reconciler.reconcile(update_operation, update_request)
      after
        Repo.query!(
          "ALTER TABLE repositories DROP CONSTRAINT test_github_provider_resource_update_storage"
        )
      end

    assert {:error, {:retryable, :integration_storage_unavailable}} = result

    unchanged = Ash.get!(Repository, repository.id, authorize?: false)
    assert unchanged.name == "update-storage-initial"
    assert unchanged.provider_sequence == 1

    assert {:ok, recovered} = Reconciler.reconcile(update_operation, update_request)
    assert recovered.state == "reconciled"

    updated = Ash.get!(Repository, repository.id, authorize?: false)
    assert updated.name == "update-storage-blocked"
    assert updated.provider_sequence == 2
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

  test "cyclic review comment parents are classified before provider-neutral writes" do
    context = reconciliation_context("cyclic-comment-parents")
    request = request(context, "pull_request", "PR_cyclic_comments", "delivery-cyclic-comments")
    operation = reconciliation_operation!(context, request, "cyclic-comments")

    comments = [
      %Adapter.ReviewCommentSnapshot{
        node_id: "PRRC_cycle_a",
        parent_comment_node_id: "PRRC_cycle_b",
        body: "Cycle A",
        state: "published"
      },
      %Adapter.ReviewCommentSnapshot{
        node_id: "PRRC_cycle_b",
        parent_comment_node_id: "PRRC_cycle_a",
        body: "Cycle B",
        state: "published"
      }
    ]

    invalid_snapshot =
      snapshot(1, "open", "PR_cyclic_comments", "R_cyclic_comments")
      |> Map.put(:review_comments, comments)

    Provider.put(%{{"pull_request", "PR_cyclic_comments"} => {:ok, invalid_snapshot}})

    assert {:error, {:terminal, :invalid_provider_response}} =
             Reconciler.reconcile(operation, request)

    outcome =
      SyncOutcome
      |> Ash.Query.filter(operation_id == ^operation.id)
      |> Ash.read_one!(authorize?: false)

    assert outcome.state == "terminal"
    assert outcome.failure_code == "invalid_provider_response"
    assert Repo.aggregate(Repository, :count) == 0
  end

  test "malformed requested-object collections are classified before root matching" do
    cases = [
      {"review-comment-nil", "review_comment", :review_comments, nil},
      {"review-comment-map", "review_comment", :review_comments, [%{}]},
      {"check-run-nil", "check_run", :check_runs, nil},
      {"check-run-map", "check_run", :check_runs, [%{}]}
    ]

    for {case_label, object_type, field, malformed_collection} <- cases do
      label = "malformed-#{case_label}"
      context = reconciliation_context(label)
      object_id = "#{object_type}_requested"
      request = request(context, object_type, object_id, "delivery-#{label}")
      operation = reconciliation_operation!(context, request, label)

      invalid_snapshot =
        snapshot(1, "open", "PR_#{label}", "R_#{label}")
        |> Map.put(field, malformed_collection)

      Provider.put(%{{object_type, object_id} => {:ok, invalid_snapshot}})

      assert {:error, {:terminal, :invalid_provider_response}} =
               Reconciler.reconcile(operation, request)

      outcome =
        SyncOutcome
        |> Ash.Query.filter(operation_id == ^operation.id)
        |> Ash.read_one!(authorize?: false)

      assert outcome.state == "terminal"
      assert outcome.failure_code == "invalid_provider_response"
    end

    assert Repo.aggregate(Repository, :count) == 0
  end

  test "provider resources and references cannot be reconciled by another provider source" do
    context = reconciliation_context("provider-ownership")
    request = request(context, "pull_request", "PR_provider_owner", "delivery-provider-owner")
    operation = reconciliation_operation!(context, request, "provider-owner")

    Provider.put(%{
      {"pull_request", "PR_provider_owner"} =>
        {:ok, snapshot(1, "open", "PR_provider_owner", "R_provider_owner")}
    })

    assert {:ok, outcome} = Reconciler.reconcile(operation, request)
    pull_request = Ash.get!(PullRequest, outcome.resource_id, authorize?: false)

    {:ok, other_source} =
      Integrations.ensure_provider_source("other-provider-#{Ecto.UUID.generate()}", "Other")

    assert {:error, :forbidden} =
             SoftwareProving.upsert_provider_resource(
               operation,
               other_source,
               PullRequest,
               pull_request,
               %{
                 title: "Cross-provider overwrite",
                 provider_version: "v2",
                 provider_sequence: 2,
                 provider_updated_at: ~U[2026-07-14 12:02:00Z]
               }
             )

    unchanged = Ash.get!(PullRequest, pull_request.id, authorize?: false)
    assert unchanged.title == "Typed GitHub reconciliation"

    {:ok, github_source} = Integrations.ensure_provider_source("github", "GitHub")

    reference =
      ExternalReference
      |> Ash.Query.filter(external_id == "pull_request:PR_provider_owner")
      |> Ash.read_one!(authorize?: false)

    assert {:error, :forbidden} =
             ExternalRefs.upsert_provider_reference(operation, github_source, %{
               provider: "gitlab",
               object_type: reference.object_type,
               external_id: reference.external_id,
               url: reference.url,
               resource_type: reference.resource_type,
               resource_id: reference.resource_id
             })

    assert Ash.get!(ExternalReference, reference.id, authorize?: false).provider == "github"
  end

  test "sparse reference updates preserve a known provider URL for nil or blank values" do
    context = reconciliation_context("sparse-reference-url")

    request =
      request(
        context,
        "pull_request",
        "PR_sparse_reference_url",
        "delivery-sparse-reference-url"
      )

    operation = reconciliation_operation!(context, request, "initial")

    Provider.put(%{
      {"pull_request", "PR_sparse_reference_url"} =>
        {:ok,
         snapshot(
           1,
           "open",
           "PR_sparse_reference_url",
           "R_sparse_reference_url"
         )}
    })

    assert {:ok, outcome} = Reconciler.reconcile(operation, request)
    {:ok, github_source} = Integrations.ensure_provider_source("github", "GitHub")

    reference =
      ExternalReference
      |> Ash.Query.filter(external_id == "pull_request:PR_sparse_reference_url")
      |> Ash.read_one!(authorize?: false)

    for sparse_url <- [nil, "", " \t"] do
      assert {:ok, updated} =
               ExternalRefs.upsert_provider_reference(operation, github_source, %{
                 provider: reference.provider,
                 object_type: reference.object_type,
                 external_id: reference.external_id,
                 url: sparse_url,
                 resource_type: reference.resource_type,
                 resource_id: outcome.resource_id
               })

      assert updated.url == "https://github.com/Un3qual/office-graph-backend/pull/24"
    end
  end

  test "check snapshots enforce status and conclusion invariants before writes" do
    invalid_checks = [
      {"completed-without-conclusion",
       %Adapter.CheckRunSnapshot{
         node_id: "CR_completed_without_conclusion",
         database_id: 501,
         name: "Missing conclusion",
         status: "completed",
         conclusion: nil
       }},
      {"progress-with-conclusion",
       %Adapter.CheckRunSnapshot{
         node_id: "CR_progress_with_conclusion",
         database_id: 502,
         name: "Stale conclusion",
         status: "in_progress",
         conclusion: "failure"
       }}
    ]

    for {label, check} <- invalid_checks do
      context = reconciliation_context("invalid-check-#{label}")
      pull_request_node_id = "PR_invalid_check_#{label}"
      request = request(context, "pull_request", pull_request_node_id, "delivery-#{label}")
      operation = reconciliation_operation!(context, request, label)

      invalid_snapshot =
        snapshot(1, "open", pull_request_node_id, "R_invalid_check_#{label}")
        |> Map.put(:check_runs, [check])

      Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, invalid_snapshot}})

      assert {:error, {:terminal, :invalid_provider_response}} =
               Reconciler.reconcile(operation, request)
    end

    assert Repo.aggregate(Repository, :count) == 0
  end

  test "GitHub waiting-family check states normalize to queued" do
    for {status, sequence} <- Enum.with_index(~w(requested waiting pending), 1) do
      context = reconciliation_context("github-check-status-#{status}")
      pull_request_node_id = "PR_github_check_status_#{status}"
      request = request(context, "pull_request", pull_request_node_id, "delivery-#{status}")
      operation = reconciliation_operation!(context, request, status)

      check = %Adapter.CheckRunSnapshot{
        node_id: "CR_github_check_status_#{status}",
        database_id: 510 + sequence,
        name: "GitHub #{status} check",
        status: status,
        conclusion: nil
      }

      provider_snapshot =
        snapshot(1, "open", pull_request_node_id, "R_github_check_status_#{status}")
        |> Map.put(:check_runs, [check])

      Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, provider_snapshot}})

      assert {:ok, _outcome} = Reconciler.reconcile(operation, request)

      persisted =
        CheckRun
        |> Ash.Query.filter(name == ^check.name)
        |> Ash.read_one!(authorize?: false)

      assert persisted.status == "queued"
      assert persisted.conclusion == nil
    end
  end

  test "GitHub stale check conclusions are preserved" do
    context = reconciliation_context("github-stale-conclusion")
    pull_request_node_id = "PR_github_stale_conclusion"
    request = request(context, "pull_request", pull_request_node_id, "delivery-stale")
    operation = reconciliation_operation!(context, request, "stale-conclusion")

    check = %Adapter.CheckRunSnapshot{
      node_id: "CR_github_stale_conclusion",
      database_id: 520,
      name: "GitHub stale check",
      status: "completed",
      conclusion: "stale"
    }

    provider_snapshot =
      snapshot(1, "open", pull_request_node_id, "R_github_stale_conclusion")
      |> Map.put(:check_runs, [check])

    Provider.put(%{{"pull_request", pull_request_node_id} => {:ok, provider_snapshot}})

    assert {:ok, _outcome} = Reconciler.reconcile(operation, request)

    persisted =
      CheckRun
      |> Ash.Query.filter(name == ^check.name)
      |> Ash.read_one!(authorize?: false)

    assert persisted.status == "completed"
    assert persisted.conclusion == "stale"
  end

  test "review comments cannot reference absent review threads" do
    context = reconciliation_context("missing-review-thread")
    object_id = "PRRC_missing_review_thread"
    request = request(context, "review_comment", object_id, "delivery-missing-review-thread")
    operation = reconciliation_operation!(context, request, "missing-review-thread")

    invalid_snapshot =
      snapshot(1, "open", "PR_missing_review_thread", "R_missing_review_thread")
      |> Map.put(:review_comments, [
        %Adapter.ReviewCommentSnapshot{
          node_id: object_id,
          database_id: 601,
          review_thread_node_id: "PRRT_missing",
          body: "This comment points to a thread outside the snapshot.",
          state: "published"
        }
      ])

    Provider.put(%{{"review_comment", object_id} => {:ok, invalid_snapshot}})

    assert {:error, {:terminal, :invalid_provider_response}} =
             Reconciler.reconcile(operation, request)

    assert Repo.aggregate(Repository, :count) == 0
  end

  test "review replies cannot declare a different thread than their parent" do
    context = reconciliation_context("mismatched-reply-thread")
    object_id = "PRRC_mismatched_reply_thread"
    request = request(context, "review_comment", object_id, "delivery-mismatched-reply-thread")
    operation = reconciliation_operation!(context, request, "mismatched-reply-thread")

    invalid_snapshot =
      snapshot(1, "open", "PR_mismatched_reply_thread", "R_mismatched_reply_thread")
      |> Map.put(:review_threads, [
        %Adapter.ReviewThreadSnapshot{node_id: "PRRT_parent", state: "resolved"},
        %Adapter.ReviewThreadSnapshot{node_id: "PRRT_reply", state: "open"}
      ])
      |> Map.put(:review_comments, [
        %Adapter.ReviewCommentSnapshot{
          node_id: "PRRC_parent_thread",
          review_thread_node_id: "PRRT_parent",
          body: "Parent comment in the resolved thread.",
          state: "published"
        },
        %Adapter.ReviewCommentSnapshot{
          node_id: object_id,
          review_thread_node_id: "PRRT_reply",
          parent_comment_node_id: "PRRC_parent_thread",
          body: "Reply incorrectly attached to the open thread.",
          state: "published"
        }
      ])

    Provider.put(%{{"review_comment", object_id} => {:ok, invalid_snapshot}})

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
