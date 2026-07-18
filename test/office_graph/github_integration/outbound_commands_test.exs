defmodule OfficeGraph.GitHubIntegration.OutboundCommandsTest do
  use OfficeGraph.DataCase, async: false

  import OfficeGraph.SessionCaseHelpers, only: [grant_organization_role_assignment!: 1]

  defmodule UnavailableSecretStore do
    @behaviour OfficeGraph.GitHubIntegration.SecretStore

    @impl true
    def fetch(_reference, _scope), do: {:error, :unavailable}
  end

  import Ecto.Query

  alias OfficeGraph.{DurableDelivery, Foundation, GitHubIntegration, Operations, Repo}

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Installation,
    InstallationCredential,
    OutboundAction,
    OutboundCommands,
    OutboundWorker,
    PermissionEntry,
    RecordLoaderTestAdapter,
    Reconciler,
    ReconciliationRequest,
    SecretStore.TestAdapter,
    SyncOutcome
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.Integrations.IntegrationCredential
  alias OfficeGraph.SoftwareProving.{CheckRun, ReviewComment, ReviewThread}
  alias OfficeGraph.SoftwareProving.GitHub.{CheckRunExtension, ReviewCommentExtension}

  require Ash.Query

  setup tags do
    context = integrated_context(tags[:installation_scope] || :workspace)
    {:ok, context}
  end

  test "review replies enqueue once, replay safely, and record provider response identity",
       context do
    attrs = %{
      installation_id: context.installation.id,
      review_comment_id: context.comment.id,
      body: "Addressed in the proposed change.",
      expected_provider_version: context.comment.provider_version
    }

    operation = command_operation!(context, :github_review_reply, "reply:comment-9:v1", attrs)

    assert {:ok, first} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    assert {:ok, replay} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    assert replay.id == first.id
    assert count_jobs(first.id) == 1

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} => {:ok, %{id: "PRRC_reply_1", version: "reply-v1"}}
    })

    assert :ok = OutboundWorker.perform(job_for(first.id))
    assert Provider.calls("review_reply", "PRRC_outbound") == 1

    assert Provider.request("review_reply", "PRRC_outbound").external_installation_id ==
             context.installation.external_installation_id

    action = Ash.get!(OutboundAction, first.id, authorize?: false)
    assert action.state == "succeeded"
    assert action.provider_response_id == "PRRC_reply_1"
    assert action.provider_response_version == "reply-v1"
  end

  test "authorization decision write outages use the integration storage contract", context do
    attrs = reply_attrs(context, "Retry after authorization decision storage recovers.")

    operation =
      command_operation!(context, :github_review_reply, "reply:authorization-write", attrs)

    Repo.query!("""
    ALTER TABLE authorization_decisions
    ADD CONSTRAINT test_github_outbound_authorization_write_storage
    CHECK (action <> 'github.review.reply')
    """)

    result =
      try do
        OutboundCommands.reply_to_review(context.session, operation, attrs)
      after
        Repo.query!("""
        ALTER TABLE authorization_decisions
        DROP CONSTRAINT test_github_outbound_authorization_write_storage
        """)
      end

    assert {:error, :integration_storage_unavailable} = result
    assert Repo.aggregate(OutboundAction, :count) == 0
    assert count_jobs_for_worker() == 0
  end

  @tag installation_scope: :organization
  test "organization-scoped installations enqueue outbound actions from authorized workspace sessions",
       context do
    reply_attrs = reply_attrs(context, "Reply through the organization-scoped installation.")

    reply_operation =
      command_operation!(context, :github_review_reply, "reply:organization-scope", reply_attrs)

    assert {:ok, reply_action} =
             OutboundCommands.reply_to_review(context.session, reply_operation, reply_attrs)

    check_attrs = %{
      installation_id: context.installation.id,
      check_run_id: context.check.id,
      status: "completed",
      conclusion: "success",
      details_url: "https://example.test/checks/organization-scope",
      expected_provider_version: context.check.provider_version
    }

    check_operation =
      command_operation!(context, :github_check_update, "check:organization-scope", check_attrs)

    assert {:ok, check_action} =
             OutboundCommands.update_check(context.session, check_operation, check_attrs)

    assert is_nil(reply_action.workspace_id)
    assert is_nil(check_action.workspace_id)
    assert is_nil(job_for(reply_action.id).args["workspace_id"])
    assert is_nil(job_for(check_action.id).args["workspace_id"])

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:ok, %{id: "PRRC_organization_reply", version: "reply-v1"}},
      {"check_update", "CR_outbound"} => {:ok, %{id: "CR_outbound", version: "check-v2"}}
    })

    assert :ok = OutboundWorker.perform(job_for(reply_action.id))
    assert :ok = OutboundWorker.perform(job_for(check_action.id))
  end

  test "compatible replays return the durable action after provider state changes", context do
    attrs = reply_attrs(context, "Return the accepted durable command result.")
    operation = command_operation!(context, :github_review_reply, "reply:state-changed", attrs)

    assert {:ok, first} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    context.comment
    |> Ash.Changeset.for_update(:reconcile, %{
      state: "minimized",
      provider_version: "v2",
      provider_sequence: 2,
      operation_id: context.comment.operation_id
    })
    |> Repo.ash_update!()

    assert {:ok, replay} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    assert replay.id == first.id
    assert count_jobs(first.id) == 1
  end

  test "review replies preserve intentional body whitespace", context do
    body = "\n    indented code\n"
    attrs = reply_attrs(context, body)
    operation = command_operation!(context, :github_review_reply, "reply:whitespace", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    assert action.input["body"] == body

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} => {:ok, %{id: "reply-whitespace", version: "v1"}}
    })

    assert :ok = OutboundWorker.perform(job_for(action.id))
    assert Provider.request("review_reply", "PRRC_outbound").body == body
  end

  test "review replies reject non-published targets before enqueue", context do
    Enum.reduce(Enum.with_index(~w(pending minimized deleted), 2), context.comment, fn
      {state, sequence}, comment ->
        updated =
          comment
          |> Ash.Changeset.for_update(:reconcile, %{
            state: state,
            provider_version: "v#{sequence}",
            provider_sequence: sequence,
            operation_id: comment.operation_id
          })
          |> Repo.ash_update!()

        attrs = %{
          installation_id: context.installation.id,
          review_comment_id: updated.id,
          body: "Do not reply to a #{state} comment.",
          expected_provider_version: updated.provider_version
        }

        operation =
          command_operation!(context, :github_review_reply, "reply:#{state}", attrs)

        assert {:error, :forbidden} =
                 OutboundCommands.reply_to_review(context.session, operation, attrs)

        updated
    end)

    assert count_jobs_for_worker() == 0
    assert Provider.calls("review_reply", "PRRC_outbound") == 0
  end

  test "review replies reject replies-to-replies before enqueue", context do
    reply =
      Repo.ash_create!(ReviewComment, %{
        organization_id: context.comment.organization_id,
        workspace_id: context.comment.workspace_id,
        source_id: context.comment.source_id,
        pull_request_id: context.comment.pull_request_id,
        review_thread_id: context.comment.review_thread_id,
        parent_comment_id: context.comment.id,
        body: "Already a reply",
        author_label: "reviewer",
        state: "published",
        published_at: ~U[2026-07-14 15:59:00Z],
        provider_version: "v2",
        provider_sequence: 2,
        provider_updated_at: ~U[2026-07-14 16:01:00Z],
        sync_state: "synced",
        operation_id: context.comment.operation_id
      })

    Repo.ash_create!(ReviewCommentExtension, %{
      review_comment_id: reply.id,
      organization_id: reply.organization_id,
      workspace_id: reply.workspace_id,
      node_id: "PRRC_outbound_reply",
      database_id: 705,
      review_database_id: 706
    })

    attrs = %{
      installation_id: context.installation.id,
      review_comment_id: reply.id,
      body: "GitHub does not support nested review replies.",
      expected_provider_version: reply.provider_version
    }

    operation = command_operation!(context, :github_review_reply, "reply:nested", attrs)

    assert {:error, :forbidden} =
             OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert Repo.aggregate(OutboundAction, :count) == 0
    assert count_jobs_for_worker() == 0
  end

  test "check updates are version-guarded and use only the check adapter action", context do
    attrs = %{
      installation_id: context.installation.id,
      check_run_id: context.check.id,
      status: "completed",
      conclusion: "success",
      details_url: "https://example.test/checks/updated",
      expected_provider_version: context.check.provider_version
    }

    operation = command_operation!(context, :github_check_update, "check:update:v1", attrs)
    assert {:ok, action} = OutboundCommands.update_check(context.session, operation, attrs)

    Provider.put(%{
      {"check_update", "CR_outbound"} => {:ok, %{id: "CR_outbound", version: "check-v2"}}
    })

    assert :ok = OutboundWorker.perform(job_for(action.id))
    assert Provider.calls("check_update", "CR_outbound") == 1

    stale_attrs = %{attrs | expected_provider_version: "stale-version"}

    stale_operation =
      command_operation!(context, :github_check_update, "check:update:stale", stale_attrs)

    assert {:error, {:stale_version, :provider_version}} =
             OutboundCommands.update_check(context.session, stale_operation, stale_attrs)
  end

  test "workers reject targets whose provider version changed after enqueue", context do
    attrs = reply_attrs(context, "Do not send this after the target changes.")
    operation = command_operation!(context, :github_review_reply, "reply:delayed-stale", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    context.comment
    |> Ash.Changeset.for_update(:reconcile, %{
      provider_version: "v2",
      provider_sequence: 2,
      operation_id: context.comment.operation_id
    })
    |> Repo.ash_update!()

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} => {:ok, %{id: "must-not-send", version: "v2"}}
    })

    assert {:cancel, "stale_provider_version"} = OutboundWorker.perform(job_for(action.id))
    assert Provider.calls("review_reply", "PRRC_outbound") == 0

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "terminal"
    assert action.failure_code == "stale_provider_version"
  end

  test "workers reject queued review replies after their thread becomes non-actionable",
       context do
    attrs = reply_attrs(context, "Do not send this after the thread resolves.")

    operation =
      command_operation!(context, :github_review_reply, "reply:resolved-thread", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    ReviewThread
    |> Ash.get!(context.comment.review_thread_id, authorize?: false)
    |> Ash.Changeset.for_update(:reconcile, %{
      state: "resolved",
      resolved_at: ~U[2026-07-14 16:01:00Z],
      provider_version: "thread-v2",
      provider_sequence: 2,
      provider_updated_at: ~U[2026-07-14 16:01:00Z],
      operation_id: context.comment.operation_id
    })
    |> Repo.ash_update!()

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:ok, %{id: "must-not-send-after-resolution", version: "v2"}}
    })

    assert {:cancel, "stale_provider_version"} = OutboundWorker.perform(job_for(action.id))
    assert Provider.calls("review_reply_lookup", action.id) == 1
    assert Provider.calls("review_reply", "PRRC_outbound") == 0

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "terminal"
    assert action.failure_code == "stale_provider_version"
  end

  test "command installation lookup outages do not create actions or jobs", context do
    attrs = reply_attrs(context, "Retry command creation after storage recovers.")
    operation = command_operation!(context, :github_review_reply, "reply:lookup-outage", attrs)

    RecordLoaderTestAdapter.configure!(%{Installation => {:error, :database_unavailable}})

    assert {:error, :integration_storage_unavailable} =
             OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert Repo.aggregate(OutboundAction, :count) == 0
    assert count_jobs_for_worker() == 0
  end

  test "command permission lookup outages do not masquerade as missing grants", context do
    attrs = reply_attrs(context, "Retry permission validation after storage recovers.")

    operation =
      command_operation!(context, :github_review_reply, "reply:permission-outage", attrs)

    RecordLoaderTestAdapter.configure!(%{PermissionEntry => {:error, :database_unavailable}})

    assert {:error, :integration_storage_unavailable} =
             OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert Repo.aggregate(OutboundAction, :count) == 0
    assert count_jobs_for_worker() == 0
  end

  test "command target lookup outages do not masquerade as forbidden targets", context do
    attrs = reply_attrs(context, "Retry target validation after storage recovers.")
    operation = command_operation!(context, :github_review_reply, "reply:target-outage", attrs)

    RecordLoaderTestAdapter.configure!(%{ReviewComment => {:error, :database_unavailable}})

    assert {:error, :integration_storage_unavailable} =
             OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert Repo.aggregate(OutboundAction, :count) == 0
    assert count_jobs_for_worker() == 0
  end

  test "command result lookup outages do not create a second action", context do
    attrs = reply_attrs(context, "Retry after the durable command result can be read.")
    operation = command_operation!(context, :github_review_reply, "reply:result-outage", attrs)

    RecordLoaderTestAdapter.configure!(%{OutboundAction => {:error, :database_unavailable}})

    assert {:error, :integration_storage_unavailable} =
             OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert Repo.aggregate(OutboundAction, :count) == 0
    assert count_jobs_for_worker() == 0
  end

  test "command extension lookup outages do not masquerade as forbidden targets", context do
    RecordLoaderTestAdapter.configure!(%{})

    check_attrs = %{
      installation_id: context.installation.id,
      check_run_id: context.check.id,
      status: "completed",
      conclusion: "success",
      details_url: "https://example.test/checks/storage-recovers",
      expected_provider_version: context.check.provider_version
    }

    cases = [
      {ReviewCommentExtension, :github_review_reply, "reply:extension-outage",
       reply_attrs(context, "Retry extension validation after storage recovers."),
       &OutboundCommands.reply_to_review/3},
      {CheckRunExtension, :github_check_update, "check:extension-outage", check_attrs,
       &OutboundCommands.update_check/3}
    ]

    for {resource, action, key, attrs, command} <- cases do
      RecordLoaderTestAdapter.put(%{resource => {:error, :database_unavailable}})
      operation = command_operation!(context, action, key, attrs)

      assert {:error, :integration_storage_unavailable} =
               command.(context.session, operation, attrs)

      assert Repo.aggregate(OutboundAction, :count) == 0
      assert count_jobs_for_worker() == 0
    end
  end

  test "command provenance lookup outages do not masquerade as missing provenance", context do
    attrs = reply_attrs(context, "Retry provenance validation after storage recovers.")

    operation =
      command_operation!(context, :github_review_reply, "reply:provenance-outage", attrs)

    RecordLoaderTestAdapter.configure!(%{SyncOutcome => {:error, :database_unavailable}})

    assert {:error, :integration_storage_unavailable} =
             OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert Repo.aggregate(OutboundAction, :count) == 0
    assert count_jobs_for_worker() == 0
  end

  test "outbound transaction storage failures expose only the retryable availability result",
       context do
    attrs = reply_attrs(context, "Retry after the command transaction storage recovers.")

    operation =
      command_operation!(context, :github_review_reply, "reply:transaction-outage", attrs)

    Repo.query!("""
    ALTER TABLE github_outbound_actions
    ADD CONSTRAINT test_github_outbound_transaction_storage
    CHECK (action_kind <> 'review_reply')
    """)

    result =
      try do
        OutboundCommands.reply_to_review(context.session, operation, attrs)
      after
        Repo.query!("""
        ALTER TABLE github_outbound_actions
        DROP CONSTRAINT test_github_outbound_transaction_storage
        """)
      end

    assert {:error, :integration_storage_unavailable} = result
    assert Repo.aggregate(OutboundAction, :count) == 0
    assert count_jobs_for_worker() == 0
  end

  test "transient outbound action lookup failures retry without terminalizing", context do
    attrs = reply_attrs(context, "Retry after the action record can be read.")
    operation = command_operation!(context, :github_review_reply, "reply:lookup-retry", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    job = job_for(action.id)

    RecordLoaderTestAdapter.configure!(%{
      OutboundAction => {:error, :database_unavailable}
    })

    assert {:error, "integration_storage_unavailable"} = OutboundWorker.perform(job)

    assert Ash.get!(OutboundAction, action.id, authorize?: false).state == "pending"
    refute Map.has_key?(Repo.get!(Oban.Job, job.id).meta, "terminal_failure_code")
  end

  test "exhausted action lookup retries terminalization until the action can be persisted",
       context do
    attrs = reply_attrs(context, "Persist terminal state after storage recovers.")
    operation = command_operation!(context, :github_review_reply, "reply:lookup-exhausted", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    job = job_for(action.id)

    RecordLoaderTestAdapter.configure!(%{
      OutboundAction => {:error, :database_unavailable}
    })

    assert {:snooze, 5} = OutboundWorker.perform(%{job | attempt: job.max_attempts})

    staged_job = Repo.get!(Oban.Job, job.id)
    assert staged_job.meta["terminal_action_id"] == action.id
    assert staged_job.meta["terminal_failure_code"] == "integration_storage_unavailable"
    assert Ash.get!(OutboundAction, action.id, authorize?: false).state == "pending"

    RecordLoaderTestAdapter.put(%{})

    assert {:cancel, "attempts_exhausted"} = OutboundWorker.perform(staged_job)

    terminal_action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert terminal_action.state == "terminal"
    assert terminal_action.failure_class == "terminal"
    assert terminal_action.failure_code == "integration_storage_unavailable"
    assert %DateTime{} = terminal_action.completed_at
  end

  test "exhausted action lookup retains terminalization when metadata staging fails", context do
    attrs = reply_attrs(context, "Do not execute after terminal staging recovers.")

    operation =
      command_operation!(context, :github_review_reply, "reply:lookup-staging-failure", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    job = job_for(action.id)

    RecordLoaderTestAdapter.configure!(%{
      OutboundAction => {:error, :database_unavailable}
    })

    Repo.query!("""
    ALTER TABLE oban_jobs
    ADD CONSTRAINT test_github_outbound_lookup_terminal_staging
    CHECK (NOT (meta ? 'terminal_action_id'))
    """)

    result =
      try do
        OutboundWorker.perform(%{job | attempt: job.max_attempts})
      after
        Repo.query!("""
        ALTER TABLE oban_jobs
        DROP CONSTRAINT test_github_outbound_lookup_terminal_staging
        """)

        RecordLoaderTestAdapter.put(%{})
      end

    assert {:snooze, 5} = result
    refute Map.has_key?(Repo.get!(Oban.Job, job.id).meta, "terminal_action_id")

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:ok, %{id: "must-not-send-after-exhaustion", version: "v1"}}
    })

    replay_job = %{
      Repo.get!(Oban.Job, job.id)
      | attempt: job.max_attempts + 1,
        max_attempts: job.max_attempts + 1
    }

    assert {:cancel, "attempts_exhausted"} = OutboundWorker.perform(replay_job)
    assert Provider.calls("review_reply_lookup", action.id) == 0
    assert Provider.calls("review_reply", "PRRC_outbound") == 0

    terminal_action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert terminal_action.state == "terminal"
    assert terminal_action.failure_class == "terminal"
    assert terminal_action.failure_code == "integration_storage_unavailable"
  end

  test "provider access waits for a durable action attempt marker", context do
    attrs = reply_attrs(context, "Do not execute without durable attempt provenance.")
    operation = command_operation!(context, :github_review_reply, "reply:attempt-marker", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:ok, %{id: "must-not-send-without-attempt-marker", version: "v1"}}
    })

    Repo.query!("""
    ALTER TABLE github_outbound_actions
    ADD CONSTRAINT test_github_outbound_attempt_marker
    CHECK (attempted_at IS NULL)
    """)

    result =
      try do
        OutboundWorker.perform(job_for(action.id))
      after
        Repo.query!("""
        ALTER TABLE github_outbound_actions
        DROP CONSTRAINT test_github_outbound_attempt_marker
        """)
      end

    assert {:error, "integration_storage_unavailable"} = result
    assert Provider.calls("review_reply_lookup", action.id) == 0
    assert Provider.calls("review_reply", "PRRC_outbound") == 0

    pending_action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert pending_action.state == "pending"
    assert is_nil(pending_action.attempted_at)
  end

  test "terminal action writes stage intent before retrying persistence", context do
    attrs = reply_attrs(context, "Persist the terminal result after storage recovers.")
    operation = command_operation!(context, :github_review_reply, "reply:terminal-write", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    job = job_for(action.id)

    Provider.put(%{{"review_reply", "PRRC_outbound"} => {:error, :permission_denied}})

    Repo.query!("""
    ALTER TABLE github_outbound_actions
    ADD CONSTRAINT test_github_outbound_terminal_write
    CHECK (state <> 'terminal')
    """)

    result =
      try do
        OutboundWorker.perform(job)
      rescue
        error -> {:raised, error}
      after
        Repo.query!("""
        ALTER TABLE github_outbound_actions
        DROP CONSTRAINT test_github_outbound_terminal_write
        """)
      end

    assert {:snooze, 5} = result

    staged_job = Repo.get!(Oban.Job, job.id)
    assert staged_job.meta["terminal_action_id"] == action.id
    assert staged_job.meta["terminal_failure_class"] == "authorization"
    assert staged_job.meta["terminal_failure_code"] == "permission_denied"
    assert staged_job.meta["terminal_result_code"] == "permission_denied"
    assert Ash.get!(OutboundAction, action.id, authorize?: false).state == "pending"

    assert {:cancel, "permission_denied"} = OutboundWorker.perform(staged_job)

    terminal_action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert terminal_action.state == "terminal"
    assert terminal_action.failure_class == "authorization"
    assert terminal_action.failure_code == "permission_denied"
    assert trace_counts(action, "github.review_reply.terminal") == {1, 1}

    Repo.query!(
      "DELETE FROM revisions WHERE operation_id = $1 AND revision_type = $2",
      [Ecto.UUID.dump!(action.operation_id), "github.review_reply.terminal"]
    )

    assert {:cancel, "permission_denied"} = OutboundWorker.perform(staged_job)
    assert trace_counts(action, "github.review_reply.terminal") == {1, 1}
  end

  test "successful check updates stage provider identity before action persistence", context do
    attrs = %{
      installation_id: context.installation.id,
      check_run_id: context.check.id,
      status: "completed",
      conclusion: "success",
      details_url: "https://example.test/checks/staged-success",
      expected_provider_version: context.check.provider_version
    }

    operation =
      command_operation!(context, :github_check_update, "check:staged-success", attrs)

    assert {:ok, action} = OutboundCommands.update_check(context.session, operation, attrs)
    job = job_for(action.id)

    Provider.put(%{
      {"check_update", "CR_outbound"} => {:ok, %{id: "CR_staged_success", version: "check-v2"}}
    })

    Repo.query!("""
    ALTER TABLE github_outbound_actions
    ADD CONSTRAINT test_github_outbound_success_write
    CHECK (state <> 'succeeded')
    """)

    result =
      try do
        OutboundWorker.perform(job)
      after
        Repo.query!("""
        ALTER TABLE github_outbound_actions
        DROP CONSTRAINT test_github_outbound_success_write
        """)
      end

    assert {:snooze, 5} = result

    staged_job = Repo.get!(Oban.Job, job.id)
    assert staged_job.meta["successful_action_id"] == action.id
    assert staged_job.meta["successful_provider_response_id"] == "CR_staged_success"
    assert staged_job.meta["successful_provider_response_version"] == "check-v2"
    assert Ash.get!(OutboundAction, action.id, authorize?: false).state == "pending"
    assert Provider.calls("check_update", "CR_outbound") == 1

    assert :ok = OutboundWorker.perform(staged_job)

    succeeded = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert succeeded.state == "succeeded"
    assert succeeded.provider_response_id == "CR_staged_success"
    assert succeeded.provider_response_version == "check-v2"
    assert Provider.calls("check_update", "CR_outbound") == 1
  end

  test "check update retries accept reconciled provider success after metadata staging fails",
       context do
    attrs = %{
      installation_id: context.installation.id,
      check_run_id: context.check.id,
      status: "completed",
      conclusion: "success",
      details_url: "https://example.test/checks/reconciled-success",
      expected_provider_version: context.check.provider_version
    }

    operation =
      command_operation!(context, :github_check_update, "check:reconciled-success", attrs)

    assert {:ok, action} = OutboundCommands.update_check(context.session, operation, attrs)
    job = job_for(action.id)

    Provider.put(%{
      {"check_update", "CR_outbound"} => {:ok, %{id: "CR_outbound", version: "check-v2"}}
    })

    Repo.query!("""
    ALTER TABLE oban_jobs
    ADD CONSTRAINT test_github_outbound_success_staging
    CHECK (NOT (meta ? 'successful_action_id'))
    """)

    result =
      try do
        OutboundWorker.perform(job)
      after
        Repo.query!("""
        ALTER TABLE oban_jobs
        DROP CONSTRAINT test_github_outbound_success_staging
        """)
      end

    assert {:snooze, 5} = result
    refute Map.has_key?(Repo.get!(Oban.Job, job.id).meta, "successful_action_id")
    assert Ash.get!(OutboundAction, action.id, authorize?: false).state == "pending"
    assert Provider.calls("check_update", "CR_outbound") == 1

    context.check
    |> Ash.Changeset.for_update(:reconcile, %{
      status: attrs.status,
      conclusion: attrs.conclusion,
      details_url: attrs.details_url,
      provider_version: "check-v2",
      provider_sequence: 2,
      operation_id: context.check.operation_id
    })
    |> Repo.ash_update!()

    assert :ok = OutboundWorker.perform(Repo.get!(Oban.Job, job.id))

    succeeded = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert succeeded.state == "succeeded"
    assert succeeded.provider_response_id == "CR_outbound"
    assert succeeded.provider_response_version == "check-v2"
    assert Provider.calls("check_update", "CR_outbound") == 1
  end

  test "transient loaded-action dependency lookups remain retryable", context do
    RecordLoaderTestAdapter.configure!(%{})

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} => {:ok, %{id: "reply-after-lookup", version: "v1"}}
    })

    for {resource, label} <- [
          {Installation, "installation"},
          {InstallationCredential, "credential"},
          {ReviewComment, "target"}
        ] do
      RecordLoaderTestAdapter.put(%{})
      attrs = reply_attrs(context, "Retry after the #{label} record can be read.")

      operation =
        command_operation!(context, :github_review_reply, "reply:#{label}-lookup", attrs)

      assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

      RecordLoaderTestAdapter.put(%{resource => {:error, :database_unavailable}})

      assert {:error, "integration_storage_unavailable"} =
               OutboundWorker.perform(job_for(action.id))

      action = Ash.get!(OutboundAction, action.id, authorize?: false)
      assert action.state == "retryable"
      assert action.failure_class == "retryable"
      assert action.failure_code == "integration_storage_unavailable"
    end
  end

  test "queued and in-progress check updates do not require a conclusion", context do
    attrs = %{
      installation_id: context.installation.id,
      check_run_id: context.check.id,
      status: "in_progress",
      details_url: "https://example.test/checks/in-progress",
      expected_provider_version: context.check.provider_version
    }

    operation = command_operation!(context, :github_check_update, "check:update:progress", attrs)

    assert {:ok, action} = OutboundCommands.update_check(context.session, operation, attrs)
    assert action.state == "pending"
    assert action.input["conclusion"] == nil
  end

  test "outbound check updates reject provider-only startup failures", context do
    attrs = %{
      installation_id: context.installation.id,
      check_run_id: context.check.id,
      status: "completed",
      conclusion: "startup_failure",
      details_url: "https://example.test/checks/startup-failure",
      expected_provider_version: context.check.provider_version
    }

    operation =
      command_operation!(context, :github_check_update, "check:update:startup-failure", attrs)

    assert {:error, {:invalid_field, :conclusion}} =
             OutboundCommands.update_check(context.session, operation, attrs)

    assert count_jobs_for_worker() == 0
  end

  test "review reply retries reconcile the durable action before creating again", context do
    attrs = reply_attrs(context, "Do not duplicate an ambiguously successful reply.")

    operation =
      command_operation!(context, :github_review_reply, "reply:ambiguous-success", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    Provider.put(%{
      {"review_reply_lookup", action.id} =>
        {:ok, %{id: "PRRC_existing_reply", version: "reply-existing-v1"}},
      {"review_reply", "PRRC_outbound"} =>
        {:ok, %{id: "PRRC_duplicate_reply", version: "reply-duplicate-v1"}}
    })

    assert :ok = OutboundWorker.perform(job_for(action.id))
    assert Provider.calls("review_reply_lookup", action.id) == 1
    assert Provider.calls("review_reply", "PRRC_outbound") == 0

    request = Provider.request("review_reply_lookup", action.id)
    assert request.idempotency_key == action.id
    assert request.target_node_id == "PRRC_outbound"

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "succeeded"
    assert action.provider_response_id == "PRRC_existing_reply"
  end

  test "completed action replays restore an atomically missing trace", context do
    attrs = reply_attrs(context, "Restore traces without repeating the provider side effect.")
    operation = command_operation!(context, :github_review_reply, "reply:trace-recovery", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    job = job_for(action.id)

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:ok, %{id: "PRRC_trace_recovery", version: "reply-v1"}}
    })

    Repo.query!("""
    ALTER TABLE revisions
    ADD CONSTRAINT test_github_outbound_trace_write
    CHECK (revision_type <> 'github.review_reply.succeeded')
    """)

    result =
      try do
        OutboundWorker.perform(job)
      rescue
        error -> {:raised, error}
      after
        Repo.query!("""
        ALTER TABLE revisions
        DROP CONSTRAINT test_github_outbound_trace_write
        """)
      end

    assert {:snooze, 5} = result
    assert Ash.get!(OutboundAction, action.id, authorize?: false).state == "succeeded"
    assert trace_counts(action, "github.review_reply.succeeded") == {0, 0}
    assert Provider.calls("review_reply", "PRRC_outbound") == 1

    assert :ok = OutboundWorker.perform(job)
    assert trace_counts(action, "github.review_reply.succeeded") == {1, 1}
    assert Provider.calls("review_reply", "PRRC_outbound") == 1
  end

  test "review reply retries reconcile provider success after the target version advances",
       context do
    attrs = reply_attrs(context, "Reconcile provider success after local persistence failed.")

    operation =
      command_operation!(
        context,
        :github_review_reply,
        "reply:success-before-version-change",
        attrs
      )

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    context.comment
    |> Ash.Changeset.for_update(:reconcile, %{
      provider_version: "v2",
      provider_sequence: 2,
      operation_id: context.comment.operation_id
    })
    |> Repo.ash_update!()

    Provider.put(%{
      {"review_reply_lookup", action.id} =>
        {:ok, %{id: "PRRC_existing_after_version_change", version: "reply-existing-v2"}},
      {"review_reply", "PRRC_outbound"} =>
        {:ok, %{id: "PRRC_duplicate_after_version_change", version: "reply-duplicate-v2"}}
    })

    assert :ok = OutboundWorker.perform(job_for(action.id))
    assert Provider.calls("review_reply_lookup", action.id) == 1
    assert Provider.calls("review_reply", "PRRC_outbound") == 0

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "succeeded"
    assert action.provider_response_id == "PRRC_existing_after_version_change"
  end

  test "outbound targets must have reconciliation provenance for the selected installation",
       context do
    unique = System.unique_integer([:positive])

    {:ok, second} =
      GitHubIntegration.bind_installation(context.session, %{
        idempotency_key: "bind-outbound-second-#{unique}",
        external_installation_id: unique,
        workspace_id: context.session.workspace_id,
        app_slug: "office-graph",
        account_login: "Un3qual-second",
        account_type: "organization",
        service_principal_email: "github-service-outbound-second-#{unique}@office-graph.local",
        webhook_principal_email: "github-webhook-outbound-second-#{unique}@office-graph.local",
        webhook_secret_reference: "test-secret://github/outbound-second/#{unique}/webhook",
        app_private_key_reference: "test-secret://github/outbound-second/#{unique}/private-key",
        permissions: [%{name: "pull_requests", access_level: "write"}]
      })

    attrs = %{
      installation_id: second.installation.id,
      review_comment_id: context.comment.id,
      body: "The selected installation did not reconcile this target.",
      expected_provider_version: context.comment.provider_version
    }

    operation =
      command_operation!(context, :github_review_reply, "reply:wrong-installation", attrs)

    assert {:error, :forbidden} =
             OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert count_jobs_for_worker() == 0
  end

  test "repository writes are not representable" do
    refute function_exported?(OutboundCommands, :commit, 3)
    refute function_exported?(OutboundCommands, :merge, 3)
    refute function_exported?(OutboundCommands, :create_branch, 3)
  end

  test "insufficient installation permission is rejected before provider access", context do
    unique = System.unique_integer([:positive])

    {:ok, read_only} =
      GitHubIntegration.bind_installation(context.session, %{
        idempotency_key: "bind-outbound-read-only-#{unique}",
        external_installation_id: unique,
        workspace_id: context.session.workspace_id,
        app_slug: "office-graph",
        account_login: "Un3qual-read-only",
        account_type: "organization",
        service_principal_email: "github-service-read-only-#{unique}@office-graph.local",
        webhook_principal_email: "github-webhook-read-only-#{unique}@office-graph.local",
        webhook_secret_reference: "test-secret://github/read-only/#{unique}/webhook",
        app_private_key_reference: "test-secret://github/read-only/#{unique}/private-key",
        permissions: [%{name: "pull_requests", access_level: "read"}]
      })

    attrs = %{
      installation_id: read_only.installation.id,
      review_comment_id: context.comment.id,
      body: "This must not reach the provider.",
      expected_provider_version: context.comment.provider_version
    }

    operation = command_operation!(context, :github_review_reply, "reply:read-only", attrs)

    assert {:error, {:authorization, :installation_permission_missing}} =
             OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert count_jobs_for_worker() == 0
  end

  test "rate limits remain retryable and are exposed through safe health", context do
    attrs = reply_attrs(context, "Retry after reset.")
    operation = command_operation!(context, :github_review_reply, "reply:rate-limit", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:error, {:rate_limited, DateTime.add(DateTime.utc_now(), 30, :second)}}
    })

    assert {:snooze, delay} = OutboundWorker.perform(job_for(action.id))
    assert delay in 1..30

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "retryable"
    assert action.failure_code == "provider_rate_limited"

    assert {:ok, health} =
             GitHubIntegration.integration_health(context.session, context.installation.id)

    assert health.retryable_count == 1
    assert health.terminal_count == 0
    assert Enum.map(health.recent_failures, & &1.code) == ["provider_rate_limited"]
  end

  test "rate limits preserve the provider reset snooze when retry-state persistence fails",
       context do
    attrs = reply_attrs(context, "Honor the provider reset during a storage outage.")

    operation =
      command_operation!(context, :github_review_reply, "reply:rate-limit-write", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:error, {:rate_limited, DateTime.add(DateTime.utc_now(), 30, :second)}}
    })

    Repo.query!("""
    ALTER TABLE github_outbound_actions
    ADD CONSTRAINT test_github_outbound_rate_limit_write
    CHECK (state <> 'retryable')
    """)

    result =
      try do
        OutboundWorker.perform(job_for(action.id))
      after
        Repo.query!("""
        ALTER TABLE github_outbound_actions
        DROP CONSTRAINT test_github_outbound_rate_limit_write
        """)
      end

    assert {:snooze, delay} = result
    assert delay in 1..30
    assert Ash.get!(OutboundAction, action.id, authorize?: false).state == "pending"
    assert Provider.calls("review_reply", "PRRC_outbound") == 1
  end

  test "provider permission denials retain authorization classification", context do
    attrs = reply_attrs(context, "Classify the provider permission denial.")

    operation =
      command_operation!(context, :github_review_reply, "reply:permission-denied", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    Provider.put(%{{"review_reply", "PRRC_outbound"} => {:error, :permission_denied}})

    assert {:cancel, "permission_denied"} = OutboundWorker.perform(job_for(action.id))

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "terminal"
    assert action.failure_class == "authorization"
    assert action.failure_code == "permission_denied"

    assert {:ok, health} =
             GitHubIntegration.integration_health(context.session, context.installation.id)

    assert health.remediation_code == "reauthorize_installation"
  end

  test "provider-reported revocation atomically terminalizes the action and installation",
       context do
    attrs = reply_attrs(context, "Stop provider work after GitHub revokes the installation.")

    operation =
      command_operation!(context, :github_review_reply, "reply:installation-revoked", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    Provider.put(%{{"review_reply", "PRRC_outbound"} => {:error, :installation_revoked}})

    Repo.query!("""
    ALTER TABLE github_installations
    ADD CONSTRAINT test_github_outbound_installation_revocation
    CHECK (lifecycle_state <> 'revoked')
    """)

    try do
      assert {:snooze, 5} = OutboundWorker.perform(job_for(action.id))
      assert Ash.get!(OutboundAction, action.id, authorize?: false).state == "pending"

      assert Ash.get!(Installation, context.installation.id, authorize?: false).lifecycle_state ==
               "active"
    after
      Repo.query!("""
      ALTER TABLE github_installations
      DROP CONSTRAINT test_github_outbound_installation_revocation
      """)
    end

    staged_job = Repo.get!(Oban.Job, job_for(action.id).id)
    assert staged_job.meta["terminal_action_id"] == action.id

    assert {:cancel, "installation_revoked"} = OutboundWorker.perform(staged_job)
    assert Provider.calls("review_reply", "PRRC_outbound") == 1

    terminal_action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert terminal_action.state == "terminal"
    assert terminal_action.failure_code == "installation_revoked"

    revoked_installation = Ash.get!(Installation, context.installation.id, authorize?: false)
    assert revoked_installation.lifecycle_state == "revoked"
  end

  test "rate-limit snoozes cannot extend the fixed outbound attempt budget", context do
    attrs = reply_attrs(context, "The provider remains rate limited.")

    operation =
      command_operation!(context, :github_review_reply, "reply:rate-limit-exhausted", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:error, {:rate_limited, DateTime.add(DateTime.utc_now(), 30, :second)}}
    })

    job = job_for(action.id)
    snoozed_job = %{job | attempt: 10, max_attempts: 19}

    assert {:cancel, "attempts_exhausted"} = OutboundWorker.perform(snoozed_job)

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "terminal"
    assert action.failure_class == "terminal"
    assert action.failure_code == "provider_rate_limited"
    assert %DateTime{} = action.completed_at
  end

  test "exhausted transient retries persist a terminal action state", context do
    attrs = reply_attrs(context, "Retry budget is exhausted.")
    operation = command_operation!(context, :github_review_reply, "reply:exhausted", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    Provider.put(%{{"review_reply", "PRRC_outbound"} => {:error, :network_error}})

    job = job_for(action.id)
    exhausted_job = %{job | attempt: job.max_attempts}

    assert {:cancel, "attempts_exhausted"} = OutboundWorker.perform(exhausted_job)

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "terminal"
    assert action.failure_class == "terminal"
    assert action.failure_code == "provider_unavailable"
    assert %DateTime{} = action.completed_at
  end

  test "an unavailable outbound adapter is classified as configuration", context do
    configured = Application.fetch_env!(:office_graph, :github_adapter)

    Application.put_env(
      :office_graph,
      :github_adapter,
      OfficeGraph.GitHubIntegration.Adapter.Unavailable
    )

    on_exit(fn -> Application.put_env(:office_graph, :github_adapter, configured) end)

    attrs = reply_attrs(context, "The adapter must be configured.")

    operation =
      command_operation!(context, :github_review_reply, "reply:adapter-unavailable", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert {:cancel, "adapter_unavailable"} = OutboundWorker.perform(job_for(action.id))

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "terminal"
    assert action.failure_class == "configuration"
    assert action.failure_code == "adapter_unavailable"
    assert %DateTime{} = action.completed_at
  end

  test "unexpected persisted input is recorded as terminal instead of crashing", context do
    attrs = reply_attrs(context, "Persisted input must be allowlisted.")
    operation = command_operation!(context, :github_review_reply, "reply:invalid-input", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    unknown_key = "unrecognized_#{Ecto.UUID.generate()}"

    Repo.query!(
      "UPDATE github_outbound_actions SET input = $2 WHERE id::text = $1",
      [action.id, %{unknown_key => "value"}]
    )

    assert {:cancel, "invalid_provider_response"} = OutboundWorker.perform(job_for(action.id))

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "terminal"
    assert action.failure_code == "invalid_provider_response"
    assert Provider.calls("review_reply", "PRRC_outbound") == 0
  end

  test "temporary secret-store outages keep outbound work retryable", context do
    configured = Application.fetch_env!(:office_graph, :github_secret_store)
    Application.put_env(:office_graph, :github_secret_store, UnavailableSecretStore)
    on_exit(fn -> Application.put_env(:office_graph, :github_secret_store, configured) end)

    attrs = reply_attrs(context, "Retry secret resolution.")

    operation =
      command_operation!(context, :github_review_reply, "reply:secret-unavailable", attrs)

    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert {:error, "provider_unavailable"} =
             OutboundWorker.perform(job_for(action.id))

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "retryable"
    assert action.failure_code == "provider_unavailable"
  end

  test "missing outbound secrets are classified as credential failures", context do
    TestAdapter.put(%{})

    attrs = reply_attrs(context, "Resolve the installation credential.")
    operation = command_operation!(context, :github_review_reply, "reply:missing-secret", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    assert {:cancel, "invalid_credential"} = OutboundWorker.perform(job_for(action.id))

    action = Ash.get!(OutboundAction, action.id, authorize?: false)
    assert action.state == "terminal"
    assert action.failure_class == "terminal"
    assert action.failure_code == "invalid_credential"

    assert {:ok, health} =
             GitHubIntegration.integration_health(context.session, context.installation.id)

    assert health.remediation_code == "rotate_credentials"
  end

  test "health remediation considers classified failures outside the display limit", context do
    TestAdapter.put(%{})

    invalid_attrs = reply_attrs(context, "Record an older credential failure.")

    invalid_operation =
      command_operation!(
        context,
        :github_review_reply,
        "reply:older-invalid-secret",
        invalid_attrs
      )

    assert {:ok, invalid_action} =
             OutboundCommands.reply_to_review(context.session, invalid_operation, invalid_attrs)

    assert {:cancel, "invalid_credential"} = OutboundWorker.perform(job_for(invalid_action.id))

    TestAdapter.put(%{context.credential.secret_reference => "private-key-outbound"})

    rate_limited_attrs = reply_attrs(context, "Record a newer retryable failure.")

    rate_limited_operation =
      command_operation!(
        context,
        :github_review_reply,
        "reply:newer-rate-limit",
        rate_limited_attrs
      )

    assert {:ok, rate_limited_action} =
             OutboundCommands.reply_to_review(
               context.session,
               rate_limited_operation,
               rate_limited_attrs
             )

    Provider.put(%{
      {"review_reply", "PRRC_outbound"} =>
        {:error, {:rate_limited, DateTime.add(DateTime.utc_now(), 30, :second)}}
    })

    assert {:snooze, _delay} = OutboundWorker.perform(job_for(rate_limited_action.id))

    assert {:ok, health} =
             GitHubIntegration.integration_health(context.session, context.installation.id,
               limit: 1
             )

    assert Enum.map(health.recent_failures, & &1.code) == ["provider_rate_limited"]
    assert health.remediation_code == "rotate_credentials"
  end

  test "terminal outbound failures remain classified in durable job history", context do
    TestAdapter.put(%{})

    attrs = reply_attrs(context, "Preserve the terminal reason.")
    operation = command_operation!(context, :github_review_reply, "reply:job-history", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)
    job = job_for(action.id)

    assert {:cancel, "invalid_credential"} = OutboundWorker.perform(job)

    terminal_job =
      job.id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(%{
        state: "cancelled",
        cancelled_at: DateTime.utc_now()
      })
      |> Repo.update!()

    assert terminal_job.meta["terminal_failure_code"] == "invalid_credential"
    assert {:ok, summaries} = DurableDelivery.list_terminal_jobs(context.session)

    assert %{failure_code: "invalid_credential"} =
             Enum.find(summaries, &(&1.id == terminal_job.id))
  end

  test "revoked credentials fail terminally with a rotate-credential remediation", context do
    attrs = reply_attrs(context, "Credential must be active.")
    operation = command_operation!(context, :github_review_reply, "reply:credential", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    context.credential
    |> Ash.Changeset.for_update(:set_status, %{status: "revoked"})
    |> Repo.ash_update!()

    assert {:cancel, "invalid_credential"} = OutboundWorker.perform(job_for(action.id))

    assert {:ok, health} =
             GitHubIntegration.integration_health(context.session, context.installation.id)

    assert health.credential_posture == "invalid"
    assert health.terminal_count == 1
    assert health.remediation_code == "rotate_credentials"
  end

  test "revoked installations fail terminally with reauthorization guidance", context do
    attrs = reply_attrs(context, "Installation must be active.")
    operation = command_operation!(context, :github_review_reply, "reply:installation", attrs)
    assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)

    context.installation
    |> Ash.Changeset.for_update(:set_lifecycle, %{lifecycle_state: "revoked"})
    |> Repo.ash_update!()

    assert {:cancel, "installation_revoked"} = OutboundWorker.perform(job_for(action.id))

    assert {:ok, health} =
             GitHubIntegration.integration_health(context.session, context.installation.id)

    assert health.lifecycle == "revoked"
    assert health.terminal_count == 1
    assert health.remediation_code == "reauthorize_installation"
  end

  defp integrated_context(installation_scope) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    private_key_reference = "test-secret://github/outbound/private-key"

    workspace_id =
      if installation_scope == :organization, do: nil, else: bootstrap.workspace.id

    if installation_scope == :organization do
      grant_organization_role_assignment!(bootstrap)
    end

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-outbound",
        external_installation_id: System.unique_integer([:positive]),
        workspace_id: workspace_id,
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-outbound@office-graph.local",
        webhook_principal_email: "github-webhook-outbound@office-graph.local",
        webhook_secret_reference: "test-secret://github/outbound/webhook",
        app_private_key_reference: private_key_reference,
        permissions: [
          %{name: "checks", access_level: "write"},
          %{name: "pull_requests", access_level: "write"}
        ]
      })

    TestAdapter.put(%{private_key_reference => "private-key-outbound"})
    credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))

    credential_record =
      Ash.get!(IntegrationCredential, credential.credential_id, authorize?: false)

    request =
      ReconciliationRequest.new!(%{
        installation_id: bound.installation.id,
        object_type: "pull_request",
        object_id: "PR_outbound",
        delivery_id: "delivery-outbound"
      })

    {:ok, system_request} =
      Operations.new_system_operation_request(%{
        organization_id: bootstrap.organization.id,
        workspace_id: workspace_id,
        principal_id: bound.installation.service_principal_id,
        action: :integration_reconcile,
        authority_basis: "github_installation:#{bound.installation.id}",
        causation_key: "github_delivery:delivery-outbound",
        idempotency_scope: "github:object",
        idempotency_key: "pull_request:PR_outbound:v1",
        credential_id: credential.credential_id
      })

    {:ok, operation} = Operations.start_system_operation(system_request)
    Provider.put(%{{"pull_request", "PR_outbound"} => {:ok, snapshot()}})
    assert {:ok, _outcome} = Reconciler.reconcile(operation, request)

    comment = ReviewComment |> Ash.Query.filter(body == "Outbound review") |> Ash.read_one!()
    check = CheckRun |> Ash.Query.filter(name == "Outbound check") |> Ash.read_one!()

    %{
      session: bootstrap.session,
      installation: bound.installation,
      credential: credential_record,
      comment: comment,
      check: check
    }
  end

  defp command_operation!(context, action, key, attrs) do
    {:ok, operation} = Operations.start_command(context.session, action, key, attrs)
    operation
  end

  defp reply_attrs(context, body) do
    %{
      installation_id: context.installation.id,
      review_comment_id: context.comment.id,
      body: body,
      expected_provider_version: context.comment.provider_version
    }
  end

  defp count_jobs(action_id) do
    Repo.aggregate(
      from(job in Oban.Job,
        where:
          job.worker == ^inspect(OutboundWorker) and
            fragment("?->>'action_id'", job.args) == ^action_id
      ),
      :count
    )
  end

  defp count_jobs_for_worker do
    Repo.aggregate(from(job in Oban.Job, where: job.worker == ^inspect(OutboundWorker)), :count)
  end

  defp trace_counts(action, event) do
    %{rows: [[audit_count, revision_count]]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM audit_records
           WHERE operation_id = $1 AND action = $2
             AND resource_type = 'github_outbound_action' AND resource_id = $3),
          (SELECT count(*) FROM revisions
           WHERE operation_id = $1 AND revision_type = $2
             AND resource_type = 'github_outbound_action' AND resource_id = $3)
        """,
        [Ecto.UUID.dump!(action.operation_id), event, Ecto.UUID.dump!(action.id)]
      )

    {audit_count, revision_count}
  end

  defp job_for(action_id) do
    Repo.one!(
      from job in Oban.Job,
        where:
          job.worker == ^inspect(OutboundWorker) and
            fragment("?->>'action_id'", job.args) == ^action_id
    )
  end

  defp snapshot do
    %Adapter.ReconciliationSnapshot{
      provider_version: "v1",
      provider_sequence: 1,
      provider_updated_at: ~U[2026-07-14 16:00:00Z],
      repository: %Adapter.RepositorySnapshot{
        node_id: "R_outbound",
        database_id: 701,
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        owner_login: "Un3qual",
        default_ref_name: "main",
        visibility: "private",
        url: "https://github.com/Un3qual/office-graph-backend"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: "PR_outbound",
        database_id: 702,
        number: 24,
        title: "Outbound actions",
        state: "open",
        is_draft: false,
        url: "https://github.com/Un3qual/office-graph-backend/pull/24"
      },
      review_threads: [
        %Adapter.ReviewThreadSnapshot{node_id: "PRRT_outbound", state: "open"}
      ],
      review_comments: [
        %Adapter.ReviewCommentSnapshot{
          node_id: "PRRC_outbound",
          database_id: 703,
          review_thread_node_id: "PRRT_outbound",
          body: "Outbound review",
          author_label: "review-bot",
          state: "published",
          published_at: ~U[2026-07-14 15:58:00Z],
          url: "https://github.com/Un3qual/office-graph-backend/pull/24#discussion_r703"
        }
      ],
      check_runs: [
        %Adapter.CheckRunSnapshot{
          node_id: "CR_outbound",
          database_id: 704,
          name: "Outbound check",
          status: "completed",
          conclusion: "failure",
          details_url: "https://example.test/checks/704",
          completed_at: ~U[2026-07-14 15:59:00Z]
        }
      ]
    }
  end
end
