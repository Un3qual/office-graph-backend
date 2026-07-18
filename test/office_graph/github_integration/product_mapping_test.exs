defmodule OfficeGraph.GitHubIntegration.ProductMappingTest do
  use OfficeGraph.DataCase, async: false

  import OfficeGraph.SessionCaseHelpers

  alias OfficeGraph.{Content, Foundation, GitHubIntegration, Operations, Repo, WorkGraph}
  alias OfficeGraph.ExternalRefs.ExternalReference

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    OutboundAction,
    RecordLoaderTestAdapter,
    Reconciler,
    ReconciliationRequest
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.GitHubIntegration.SecretStore.TestAdapter, as: SecretStore
  alias OfficeGraph.SoftwareProving.{Repository, ReviewComment, ReviewThread}
  alias OfficeGraph.WorkGraph.{GraphItem, GraphRelationship, RelationshipRequest, Signal}

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
    signal = Ash.get!(Signal, signal_id, authorize?: false)
    assert signal.state == "open"

    {:ok, task_operation} =
      Operations.start_operation(context.bootstrap.session, :proposed_change_apply)

    assert {:ok, %{task: task}} =
             WorkGraph.create_task(
               context.bootstrap.session,
               task_operation,
               signal,
               %{
                 title: "Investigate the provider check",
                 body: "Keep this user-owned reference independent from signal lifecycle."
               }
             )

    check_reference =
      ExternalReference
      |> Ash.Query.filter(object_type == "check_run")
      |> Ash.read_one!(authorize?: false)

    reference_item =
      GraphItem
      |> Ash.Query.filter(
        resource_type == "external_reference" and resource_id == ^check_reference.id
      )
      |> Ash.read_one!(authorize?: false)

    {:ok, relationship_operation} =
      Operations.start_operation(context.bootstrap.session, :graph_relationship_create)

    assert {:ok, unrelated_reference_relationship} =
             WorkGraph.create_relationship(
               context.bootstrap.session,
               relationship_operation,
               RelationshipRequest.new!(%{
                 definition_key: "references_external",
                 source_item_id: task.graph_item_id,
                 target_item_id: reference_item.id,
                 workspace_id: context.bootstrap.workspace.id
               })
             )

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

    assert Ash.get!(GraphRelationship, unrelated_reference_relationship.id, authorize?: false).lifecycle ==
             "active"

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

  test "signals close when provider work leaves the authoritative pull request snapshot" do
    context = context("missing-provider-work")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-missing-provider-work"
      })

    base_snapshot = mapping_snapshot()
    [check] = base_snapshot.check_runs

    current = %{
      base_snapshot
      | check_runs: [
          %{
            check
            | provider_version: "check-v1",
              provider_sequence: 10,
              provider_updated_at: ~U[2026-07-14 12:59:00Z]
          }
        ]
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, current}})

    assert {:ok, current_outcome} =
             Reconciler.reconcile(operation!(context, request, "current-work"), request)

    assert length(current_outcome.signal_ids) == 2

    comment =
      ReviewComment
      |> Ash.Query.filter(state == "published")
      |> Ash.read_one!(authorize?: false)

    without_prior_work = %{
      current
      | provider_version: "v4",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z],
        review_comments: [],
        check_runs: []
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, without_prior_work}})

    assert {:ok, missing_outcome} =
             Reconciler.reconcile(operation!(context, request, "missing-work"), request)

    assert missing_outcome.signal_ids == []

    tombstoned_comment = Ash.get!(ReviewComment, comment.id, authorize?: false)
    assert tombstoned_comment.state == "deleted"
    assert tombstoned_comment.provider_version != comment.provider_version

    assert Enum.all?(current_outcome.signal_ids, fn signal_id ->
             Ash.get!(Signal, signal_id, authorize?: false).state == "closed"
           end)

    assert Repo.aggregate(Signal, :count) == 2

    reappeared = %{
      without_prior_work
      | review_comments: current.review_comments,
        check_runs: current.check_runs
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, reappeared}})

    assert {:ok, reappeared_outcome} =
             Reconciler.reconcile(operation!(context, request, "reappeared-work"), request)

    assert Enum.sort(reappeared_outcome.signal_ids) == Enum.sort(current_outcome.signal_ids)
    assert Ash.get!(ReviewComment, comment.id, authorize?: false).state == "published"

    assert Enum.all?(reappeared_outcome.signal_ids, fn signal_id ->
             Ash.get!(Signal, signal_id, authorize?: false).state == "open"
           end)

    assert Repo.aggregate(Signal, :count) == 2
  end

  test "a requested check outside the current head is retained but non-actionable" do
    context = context("requested-outside-current-head")

    pull_request_request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-current-head-check"
      })

    failing = %{mapping_snapshot() | review_comments: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, failing}})

    assert {:ok, first_outcome} =
             Reconciler.reconcile(
               operation!(context, pull_request_request, "current-head-check"),
               pull_request_request
             )

    assert [signal_id] = first_outcome.signal_ids
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "open"

    [historical_check] = failing.check_runs

    historical_check =
      historical_check
      |> Map.put(:current?, false)
      |> Map.merge(%{
        provider_version: "historical-check-v2",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z]
      })

    requested_snapshot = %{
      failing
      | provider_version: "v4",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z],
        check_runs: [historical_check]
    }

    check_request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "check_run",
        object_id: historical_check.node_id,
        pull_request_id: "PR_mapping_44",
        delivery_id: "delivery-historical-check"
      })

    Provider.put(%{{"check_run", historical_check.node_id} => {:ok, requested_snapshot}})

    assert {:ok, historical_outcome} =
             Reconciler.reconcile(
               operation!(context, check_request, "historical-check"),
               check_request
             )

    assert historical_outcome.signal_ids == []
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "closed"
  end

  test "authoritative-absence read outages remain retryable without closing signals" do
    context = context("missing-provider-work-read-unavailable")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-missing-provider-work-read-unavailable"
      })

    current = %{mapping_snapshot() | check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, current}})

    assert {:ok, current_outcome} =
             Reconciler.reconcile(operation!(context, request, "current-work"), request)

    assert [signal_id] = current_outcome.signal_ids
    [comment] = current.review_comments

    without_comment = %{
      current
      | provider_version: "v4",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z],
        review_comments: []
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, without_comment}})
    RecordLoaderTestAdapter.configure!(%{ReviewComment => {:error, :database_unavailable}})

    assert {:error, {:retryable, :integration_storage_unavailable}} =
             Reconciler.reconcile(operation!(context, request, "missing-work"), request)

    persisted_comment =
      ReviewComment
      |> Ash.Query.filter(body == ^comment.body)
      |> Ash.read_one!(authorize?: false)

    assert persisted_comment.state == "published"
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "open"
  end

  test "stale child snapshots do not close provider work missing from that stale view" do
    context = context("stale-missing-provider-work")

    pull_request_request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-current-provider-work"
      })

    current = mapping_snapshot()
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, current}})

    assert {:ok, current_outcome} =
             Reconciler.reconcile(
               operation!(context, pull_request_request, "current-provider-work"),
               pull_request_request
             )

    assert length(current_outcome.signal_ids) == 2
    [comment] = current.review_comments

    stale_comment_request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "review_comment",
        object_id: comment.node_id,
        delivery_id: "delivery-stale-provider-work"
      })

    stale = %{
      current
      | provider_version: "v2",
        provider_sequence: 2,
        provider_updated_at: ~U[2026-07-14 12:59:00Z],
        review_comments: [comment],
        check_runs: []
    }

    Provider.put(%{{"review_comment", comment.node_id} => {:ok, stale}})

    assert {:ok, stale_outcome} =
             Reconciler.reconcile(
               operation!(context, stale_comment_request, "stale-provider-work"),
               stale_comment_request
             )

    assert stale_outcome.signal_ids == []

    assert Enum.all?(current_outcome.signal_ids, fn signal_id ->
             Ash.get!(Signal, signal_id, authorize?: false).state == "open"
           end)
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

  test "resolved review threads do not create or retain open signals" do
    context = context("resolved-thread-signal-lifecycle")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-resolved-thread-signal-lifecycle"
      })

    open = %{mapping_snapshot() | check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, open}})

    assert {:ok, open_outcome} =
             Reconciler.reconcile(operation!(context, request, "open-thread"), request)

    assert [signal_id] = open_outcome.signal_ids
    [thread] = open.review_threads

    resolved = %{
      open
      | provider_version: "v4",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z],
        review_threads: [
          %{thread | state: "resolved", resolved_at: ~U[2026-07-14 13:01:00Z]}
        ]
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, resolved}})

    assert {:ok, resolved_outcome} =
             Reconciler.reconcile(operation!(context, request, "resolved-thread"), request)

    assert resolved_outcome.signal_ids == []
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "closed"

    first_seen_context = context("first-seen-resolved-thread")

    first_seen_request =
      ReconciliationRequest.new!(%{
        installation_id: first_seen_context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-first-seen-resolved-thread"
      })

    signal_count = Repo.aggregate(Signal, :count)

    assert {:ok, first_seen_outcome} =
             Reconciler.reconcile(
               operation!(first_seen_context, first_seen_request, "first-seen-resolved"),
               first_seen_request
             )

    assert first_seen_outcome.signal_ids == []
    assert Repo.aggregate(Signal, :count) == signal_count
  end

  test "stale open thread snapshots cannot reopen signals closed by newer thread state" do
    context = context("stale-thread-actionability")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-stale-thread-actionability"
      })

    open = %{mapping_snapshot() | check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, open}})
    open_operation = operation!(context, request, "open-thread")

    assert {:ok, open_outcome} = Reconciler.reconcile(open_operation, request)
    assert [signal_id] = open_outcome.signal_ids

    thread =
      ReviewThread
      |> Ash.Query.filter(state == "open")
      |> Ash.read_one!(authorize?: false)

    thread =
      thread
      |> Ash.Changeset.for_update(:reconcile, %{
        state: "resolved",
        resolved_at: ~U[2026-07-14 13:02:00Z],
        provider_version: "v5",
        provider_sequence: 5,
        provider_updated_at: ~U[2026-07-14 13:02:00Z],
        operation_id: open_operation.id
      })
      |> Repo.ash_update!()

    reference =
      ExternalReference
      |> Ash.Query.filter(object_type == "review_comment")
      |> Ash.read_one!(authorize?: false)

    assert {:ok, closed} =
             WorkGraph.sync_integration_signal(
               operation!(context, request, "authoritative-thread-close"),
               reference,
               %{
                 title: "Review comment from review-bot",
                 body: "Please handle the stale provider version."
               },
               false
             )

    assert closed.signal.id == signal_id
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "closed"

    [thread_snapshot] = open.review_threads

    stale_open = %{
      open
      | provider_version: "v4",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z],
        review_threads: [%{thread_snapshot | state: "open", resolved_at: nil}]
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, stale_open}})

    assert {:ok, stale_outcome} =
             Reconciler.reconcile(operation!(context, request, "stale-open-thread"), request)

    assert stale_outcome.signal_ids == []
    assert Ash.get!(ReviewThread, thread.id, authorize?: false).state == "resolved"
    assert Ash.get!(Signal, signal_id, authorize?: false).state == "closed"
  end

  test "product-signal storage failures remain retryable without partial writes" do
    context = context("signal-storage-unavailable")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-signal-storage-unavailable"
      })

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, mapping_snapshot()}})
    operation = operation!(context, request, "signal-storage-unavailable")
    repository_count = Repo.aggregate(Repository, :count)
    signal_count = Repo.aggregate(Signal, :count)

    Repo.query!("""
    ALTER TABLE graph_items
    ADD CONSTRAINT test_integration_signal_storage_unavailable
    CHECK (resource_type <> 'external_reference')
    """)

    result =
      try do
        Reconciler.reconcile(operation, request)
      after
        Repo.query!(
          "ALTER TABLE graph_items DROP CONSTRAINT test_integration_signal_storage_unavailable"
        )
      end

    assert {:error, {:retryable, :integration_storage_unavailable}} = result
    assert Repo.aggregate(Repository, :count) == repository_count
    assert Repo.aggregate(Signal, :count) == signal_count

    assert {:ok, recovered} = Reconciler.reconcile(operation, request)
    assert recovered.state == "reconciled"
    assert length(recovered.signal_ids) == 2
  end

  test "product-signal trace write outages remain retryable without partial writes" do
    context = context("signal-trace-storage-unavailable")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-signal-trace-storage-unavailable"
      })

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, mapping_snapshot()}})
    operation = operation!(context, request, "signal-trace-storage-unavailable")
    repository_count = Repo.aggregate(Repository, :count)
    signal_count = Repo.aggregate(Signal, :count)

    Repo.query!("""
    ALTER TABLE revisions
    ADD CONSTRAINT test_integration_signal_trace_storage_unavailable
    CHECK (revision_type <> 'signal.create')
    """)

    result =
      try do
        Reconciler.reconcile(operation, request)
      after
        Repo.query!("""
        ALTER TABLE revisions
        DROP CONSTRAINT test_integration_signal_trace_storage_unavailable
        """)
      end

    assert {:error, {:retryable, :integration_storage_unavailable}} = result
    assert Repo.aggregate(Repository, :count) == repository_count
    assert Repo.aggregate(Signal, :count) == signal_count

    assert {:ok, recovered} = Reconciler.reconcile(operation, request)
    assert recovered.state == "reconciled"
    assert length(recovered.signal_ids) == 2
  end

  test "actionable provider edits refresh the canonical signal content" do
    context = context("signal-content-refresh")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-signal-content-refresh"
      })

    original = %{mapping_snapshot() | check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, original}})

    assert {:ok, first_outcome} =
             Reconciler.reconcile(operation!(context, request, "original"), request)

    assert [signal_id] = first_outcome.signal_ids
    original_signal = Ash.get!(Signal, signal_id, authorize?: false)

    assert {:ok, "Please handle the stale provider version."} =
             Content.plain_text_for_document(
               context.bootstrap.session,
               original_signal.body_document_id
             )

    [original_comment] = original.review_comments

    edited = %{
      original
      | provider_version: "v4",
        provider_sequence: 4,
        provider_updated_at: ~U[2026-07-14 13:01:00Z],
        review_comments: [
          %{
            original_comment
            | body: "Use the refreshed provider version instead.",
              author_label: "updated-review-bot"
          }
        ]
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, edited}})

    assert {:ok, edited_outcome} =
             Reconciler.reconcile(operation!(context, request, "edited"), request)

    assert edited_outcome.signal_ids == [signal_id]

    refreshed_signal = Ash.get!(Signal, signal_id, authorize?: false)
    refreshed_item = Ash.get!(GraphItem, refreshed_signal.graph_item_id, authorize?: false)

    assert refreshed_signal.title == "Review comment from updated-review-bot"
    assert refreshed_item.title == refreshed_signal.title
    assert refreshed_signal.body_document_id != original_signal.body_document_id

    assert {:ok, "Use the refreshed provider version instead."} =
             Content.plain_text_for_document(
               context.bootstrap.session,
               refreshed_signal.body_document_id
             )
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

  test "review replies inherit their parent thread and its non-actionable state" do
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
      parent_comment_node_id: "PRRC_parent",
      body: "Reply review comment",
      author_label: "author",
      state: "published",
      published_at: ~U[2026-07-14 12:58:00Z]
    }

    base_snapshot = mapping_snapshot()
    [thread] = base_snapshot.review_threads

    snapshot = %{
      base_snapshot
      | review_threads: [
          %{thread | state: "resolved", resolved_at: ~U[2026-07-14 12:59:00Z]}
        ],
        review_comments: [reply, parent],
        check_runs: []
    }

    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, snapshot}})

    assert {:ok, outcome} = Reconciler.reconcile(operation!(context, request), request)
    assert outcome.signal_ids == []

    persisted_parent =
      ReviewComment
      |> Ash.Query.filter(body == "Parent review comment")
      |> Ash.read_one!(authorize?: false)

    persisted_reply =
      ReviewComment
      |> Ash.Query.filter(body == "Reply review comment")
      |> Ash.read_one!(authorize?: false)

    assert persisted_reply.parent_comment_id == persisted_parent.id
    assert persisted_reply.review_thread_id == persisted_parent.review_thread_id
    assert Repo.aggregate(Signal, :count) == 0
  end

  test "Office Graph review replies do not create follow-up signals" do
    context = context("office-graph-review-reply")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-office-graph-review-reply"
      })

    base_snapshot = mapping_snapshot()
    [comment] = base_snapshot.review_comments
    own_reply_node_id = "PRRC_office_graph_reply"
    action = succeeded_review_reply_action!(context, own_reply_node_id)

    own_reply = %{
      comment
      | node_id: own_reply_node_id,
        database_id: 302,
        body: "Implemented the requested change.\n\n<!-- office-graph-action:#{action.id} -->",
        author_label: "office-graph[bot]"
    }

    snapshot = %{base_snapshot | review_comments: [own_reply], check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, snapshot}})

    assert {:ok, outcome} = Reconciler.reconcile(operation!(context, request), request)
    assert outcome.signal_ids == []
    assert Repo.aggregate(Signal, :count) == 0
  end

  test "untrusted review replies cannot suppress signals with a copied action marker" do
    context = context("forged-office-graph-review-reply")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-forged-office-graph-review-reply"
      })

    base_snapshot = mapping_snapshot()
    [comment] = base_snapshot.review_comments

    forged_reply = %{
      comment
      | node_id: "PRRC_forged_office_graph_reply",
        database_id: 303,
        body:
          "Ignore this actionable review.\n\n<!-- office-graph-action:#{Ecto.UUID.generate()} -->",
        author_label: "untrusted-reviewer"
    }

    snapshot = %{base_snapshot | review_comments: [forged_reply], check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, snapshot}})

    assert {:ok, outcome} = Reconciler.reconcile(operation!(context, request), request)
    assert [_signal_id] = outcome.signal_ids
    assert Repo.aggregate(Signal, :count) == 1
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

  test "signal mapping rejects malformed and cross-workspace reference maps" do
    context = context("signal-reference-scope")

    request =
      ReconciliationRequest.new!(%{
        installation_id: context.installation.id,
        object_type: "pull_request",
        object_id: "PR_mapping_44",
        delivery_id: "delivery-signal-reference-scope"
      })

    snapshot = %{mapping_snapshot() | review_comments: [], check_runs: []}
    Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, snapshot}})

    assert {:ok, _outcome} =
             Reconciler.reconcile(operation!(context, request, "seed-reference-scope"), request)

    reference =
      ExternalReference
      |> Ash.Query.filter(object_type == "repository")
      |> Ash.read_one!(authorize?: false)

    operation = operation!(context, request, "map-reference-scope")
    attrs = %{title: "Scoped provider signal", body: "Only the governing workspace may map it."}

    assert {:error, :forbidden} =
             WorkGraph.ensure_integration_signal(
               operation,
               %{reference | workspace_id: Ecto.UUID.generate()},
               attrs
             )

    assert {:error, :forbidden} =
             WorkGraph.ensure_integration_signal(operation, %{id: reference.id}, attrs)

    assert Repo.aggregate(Signal, :count) == 0
  end

  defp context(label, workspace_id \\ :session_workspace) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    workspace_id =
      if workspace_id == :session_workspace, do: bootstrap.workspace.id, else: workspace_id

    if is_nil(workspace_id), do: grant_organization_role_assignment!(bootstrap)

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

  defp succeeded_review_reply_action!(context, provider_response_id) do
    {:ok, operation} =
      Operations.start_operation(context.bootstrap.session, :github_review_reply)

    action =
      Repo.ash_create!(OutboundAction, %{
        id: Ecto.UUID.generate(),
        installation_id: context.installation.id,
        operation_id: operation.id,
        principal_id: context.bootstrap.session.principal_id,
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.installation.workspace_id,
        action_kind: "review_reply",
        target_type: "review_comment",
        target_id: Ecto.UUID.generate(),
        expected_provider_version: "v1",
        input: %{}
      })

    action
    |> Ash.Changeset.for_update(:record_result, %{
      state: "succeeded",
      provider_response_id: provider_response_id,
      completed_at: DateTime.utc_now()
    })
    |> Repo.ash_update!()
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
