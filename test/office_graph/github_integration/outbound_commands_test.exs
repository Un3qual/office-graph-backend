defmodule OfficeGraph.GitHubIntegration.OutboundCommandsTest do
  use OfficeGraph.DataCase, async: false

  defmodule UnavailableSecretStore do
    @behaviour OfficeGraph.GitHubIntegration.SecretStore

    @impl true
    def fetch(_reference, _scope), do: {:error, :unavailable}
  end

  import Ecto.Query

  alias OfficeGraph.{DurableDelivery, Foundation, GitHubIntegration, Operations, Repo}

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    OutboundAction,
    OutboundCommands,
    OutboundWorker,
    Reconciler,
    ReconciliationRequest,
    SecretStore.TestAdapter
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.Integrations.IntegrationCredential
  alias OfficeGraph.SoftwareProving.{CheckRun, ReviewComment}

  require Ash.Query

  setup do
    context = integrated_context()
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

  defp integrated_context do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    private_key_reference = "test-secret://github/outbound/private-key"

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-outbound",
        external_installation_id: System.unique_integer([:positive]),
        workspace_id: bootstrap.workspace.id,
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
        workspace_id: bootstrap.workspace.id,
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
