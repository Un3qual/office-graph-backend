defmodule OfficeGraph.GitHubIntegration.ConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  alias OfficeGraph.{
    Foundation,
    GitHubIntegration,
    Operations
  }

  alias OfficeGraph.DurableDelivery.DomainEvent
  alias OfficeGraph.ExternalRefs.ExternalReference

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Installation,
    OutboundAction,
    OutboundCommands,
    OutboundWorker,
    Reconciler,
    ReconciliationRequest,
    RecordLoaderTestAdapter,
    SyncOutcome,
    WebhookReceipt
  }

  alias OfficeGraph.GitHubIntegration.Adapter.TestAdapter, as: Provider
  alias OfficeGraph.GitHubIntegration.SecretStore.TestAdapter, as: SecretStore
  alias OfficeGraph.Integrations.RawArchive
  alias OfficeGraph.Operations.OperationCorrelation
  alias OfficeGraph.SoftwareProving.{PullRequest, Repository, ReviewComment}
  alias OfficeGraph.SoftwareProving.GitHub.RepositoryExtension
  alias OfficeGraph.TestSupport.GitHubIntegrationCleanup

  require Ash.Query

  test "separate owners resolve one external installation claim without partial loser state" do
    suffix = System.unique_integer([:positive])

    [first, second] =
      with_unboxed_connection(fn ->
        [
          bootstrap_context("binding-a-#{suffix}"),
          bootstrap_context("binding-b-#{suffix}")
        ]
      end)

    register_cleanup(first)
    register_cleanup(second)

    external_installation_id = System.unique_integer([:positive])

    results =
      [first, second]
      |> Enum.map(fn context ->
        attrs =
          context
          |> binding_attrs()
          |> Map.put(:external_installation_id, external_installation_id)

        fn -> GitHubIntegration.bind_installation(context.bootstrap.session, attrs) end
      end)
      |> run_concurrently()

    assert 1 == Enum.count(results, &match?({:ok, _binding}, &1))
    assert 1 == Enum.count(results, &(&1 == {:error, :forbidden}))

    installation_count =
      with_unboxed_connection(fn ->
        Installation
        |> Ash.Query.filter(external_installation_id == ^external_installation_id)
        |> Ash.count!(authorize?: false)
      end)

    assert installation_count == 1
  end

  test "separate owners accept one webhook delivery and classify the replay as duplicate" do
    context = with_unboxed_connection(fn -> integration_context("webhook-replay") end)
    register_cleanup(context)

    delivery_id = "github-concurrency-delivery-#{Ecto.UUID.generate()}"
    body = webhook_payload(context.installation.external_installation_id)
    headers = signed_headers(delivery_id, "pull_request", body, context.webhook_secret)

    results =
      [
        fn -> WebhookReceipt.accept(headers, body) end,
        fn -> WebhookReceipt.accept(headers, body) end
      ]
      |> run_concurrently()

    assert Enum.sort(results) == Enum.sort([{:ok, :accepted}, {:ok, :duplicate}])

    counts =
      with_unboxed_connection(fn ->
        %{
          archives:
            RawArchive
            |> Ash.Query.filter(external_delivery_id == ^delivery_id)
            |> Ash.count!(authorize?: false),
          operations:
            OperationCorrelation
            |> Ash.Query.filter(
              operation_kind == "system" and idempotency_scope == "github:delivery" and
                idempotency_key == ^delivery_id
            )
            |> Ash.count!(authorize?: false),
          events:
            DomainEvent
            |> Ash.Query.filter(event_key == ^"github-delivery:#{delivery_id}")
            |> Ash.count!(authorize?: false),
          jobs: length(GitHubIntegrationCleanup.jobs_for_delivery(delivery_id))
        }
      end)

    assert counts == %{archives: 1, operations: 1, events: 1, jobs: 1}
  end

  test "separate owners preserve provider ordering across distinct reconciliation operations" do
    context = with_unboxed_connection(fn -> integration_context("reconciliation-order") end)
    register_cleanup(context)

    {older_request, newer_request, older_operation, newer_operation} =
      with_unboxed_connection(fn ->
        older_request =
          reconciliation_request(
            context,
            "review_comment",
            "PRRC_order_older",
            "delivery-order-older"
          )

        newer_request =
          reconciliation_request(
            context,
            "review_comment",
            "PRRC_order_newer",
            "delivery-order-newer"
          )

        {
          older_request,
          newer_request,
          reconciliation_operation!(context, older_request, "older"),
          reconciliation_operation!(context, newer_request, "newer")
        }
      end)

    Provider.put(%{
      {"review_comment", older_request.object_id} =>
        {:ok, reconciliation_snapshot(1, "PRRC_order_older", "Older provider title")},
      {"review_comment", newer_request.object_id} =>
        {:ok, reconciliation_snapshot(2, "PRRC_order_newer", "Newer provider title")}
    })

    results =
      [
        fn -> Reconciler.reconcile(older_operation, older_request) end,
        fn -> Reconciler.reconcile(newer_operation, newer_request) end
      ]
      |> run_concurrently()

    assert Enum.all?(results, &match?({:ok, %SyncOutcome{}}, &1))

    {repositories, pull_requests} =
      with_unboxed_connection(fn ->
        repositories =
          Repository
          |> Ash.Query.filter(organization_id == ^context.bootstrap.organization.id)
          |> Ash.read!(authorize?: false)

        pull_requests =
          PullRequest
          |> Ash.Query.filter(organization_id == ^context.bootstrap.organization.id)
          |> Ash.read!(authorize?: false)

        {repositories, pull_requests}
      end)

    assert [repository] = repositories
    assert repository.provider_sequence == 2
    assert [pull_request] = pull_requests
    assert pull_request.provider_sequence == 2
    assert pull_request.title == "Newer provider title"
  end

  test "separate owners roll back concurrent reconciliation failures before a clean retry" do
    context = with_unboxed_connection(fn -> integration_context("failure-atomicity") end)
    register_cleanup(context)

    {request, operation} =
      with_unboxed_connection(fn ->
        request =
          reconciliation_request(
            context,
            "pull_request",
            "PR_failure_atomicity",
            "delivery-failure-atomicity"
          )

        {request, reconciliation_operation!(context, request, "failure-atomicity")}
      end)

    Provider.put(%{
      {"pull_request", request.object_id} =>
        {:ok,
         reconciliation_snapshot(
           1,
           "PRRC_failure_atomicity",
           "Atomic reconciliation",
           request.object_id
         )}
    })

    RecordLoaderTestAdapter.configure!(%{
      RepositoryExtension => {:error, :database_unavailable}
    })

    results =
      [
        fn -> Reconciler.reconcile(operation, request) end,
        fn -> Reconciler.reconcile(operation, request) end
      ]
      |> run_concurrently()

    assert Enum.all?(
             results,
             &match?({:error, {:retryable, :integration_storage_unavailable}}, &1)
           )

    failed_counts =
      with_unboxed_connection(fn ->
        %{
          repositories:
            Repository
            |> Ash.Query.filter(organization_id == ^context.bootstrap.organization.id)
            |> Ash.count!(authorize?: false),
          pull_requests:
            PullRequest
            |> Ash.Query.filter(organization_id == ^context.bootstrap.organization.id)
            |> Ash.count!(authorize?: false),
          references:
            ExternalReference
            |> Ash.Query.filter(organization_id == ^context.bootstrap.organization.id)
            |> Ash.count!(authorize?: false)
        }
      end)

    assert failed_counts == %{repositories: 0, pull_requests: 0, references: 0}

    RecordLoaderTestAdapter.put(%{})

    assert {:ok, %SyncOutcome{state: "reconciled"}} =
             with_unboxed_connection(fn -> Reconciler.reconcile(operation, request) end)

    recovered_count =
      with_unboxed_connection(fn ->
        Repository
        |> Ash.Query.filter(organization_id == ^context.bootstrap.organization.id)
        |> Ash.count!(authorize?: false)
      end)

    assert recovered_count == 1
  end

  test "separate owners replay one outbound command into one action and one job" do
    context = with_unboxed_connection(fn -> outbound_context("outbound-idempotency") end)
    register_cleanup(context)

    attrs = reply_attrs(context, "Persist this command exactly once.")

    operation =
      with_unboxed_connection(fn ->
        command_operation!(context, "outbound-idempotency", attrs)
      end)

    results =
      [
        fn -> OutboundCommands.reply_to_review(context.bootstrap.session, operation, attrs) end,
        fn -> OutboundCommands.reply_to_review(context.bootstrap.session, operation, attrs) end
      ]
      |> run_concurrently()

    assert [action_id] =
             results
             |> Enum.map(fn {:ok, action} -> action.id end)
             |> Enum.uniq()

    {action_count, job_count} =
      with_unboxed_connection(fn ->
        action_count =
          OutboundAction
          |> Ash.Query.filter(operation_id == ^operation.id)
          |> Ash.count!(authorize?: false)

        {action_count, length(GitHubIntegrationCleanup.jobs_for_action(action_id))}
      end)

    assert {action_count, job_count} == {1, 1}
  end

  test "separate owners converge concurrent provider revocations on terminal actions" do
    context = with_unboxed_connection(fn -> outbound_context("revocation") end)
    register_cleanup(context)

    {actions, jobs} =
      with_unboxed_connection(fn ->
        actions =
          for attempt <- 1..2 do
            attrs = reply_attrs(context, "Provider revocation attempt #{attempt}.")
            operation = command_operation!(context, "revocation-#{attempt}", attrs)

            {:ok, action} =
              OutboundCommands.reply_to_review(context.bootstrap.session, operation, attrs)

            action
          end

        jobs = Enum.map(actions, &GitHubIntegrationCleanup.oban_job_for_action!(&1.id))
        {actions, jobs}
      end)

    Provider.put(%{
      {"review_reply", "PRRC_concurrency"} => {:error, :installation_revoked}
    })

    results =
      jobs
      |> Enum.map(fn job -> fn -> OutboundWorker.perform(job) end end)
      |> run_concurrently()

    assert Enum.all?(results, &(&1 == {:cancel, "installation_revoked"}))

    {installation, terminal_actions} =
      with_unboxed_connection(fn ->
        installation = Ash.get!(Installation, context.installation.id, authorize?: false)

        terminal_actions =
          actions
          |> Enum.map(&Ash.get!(OutboundAction, &1.id, authorize?: false))

        {installation, terminal_actions}
      end)

    assert installation.lifecycle_state == "revoked"
    assert Enum.all?(terminal_actions, &(&1.state == "terminal"))
    assert Enum.all?(terminal_actions, &(&1.failure_code == "installation_revoked"))
  end

  defp outbound_context(label) do
    context = integration_context(label)

    request =
      reconciliation_request(
        context,
        "pull_request",
        "PR_concurrency",
        "delivery-#{label}-outbound"
      )

    operation = reconciliation_operation!(context, request, "#{label}-outbound")

    Provider.put(%{
      {"pull_request", request.object_id} => {:ok, outbound_snapshot()}
    })

    {:ok, %SyncOutcome{state: "reconciled"}} = Reconciler.reconcile(operation, request)

    comment =
      ReviewComment
      |> Ash.Query.filter(
        organization_id == ^context.bootstrap.organization.id and
          body == "Concurrent outbound review"
      )
      |> Ash.read_one!(authorize?: false)

    Map.put(context, :comment, comment)
  end

  defp integration_context(label) do
    context = bootstrap_context(label)
    attrs = binding_attrs(context)
    {:ok, bound} = GitHubIntegration.bind_installation(context.bootstrap.session, attrs)

    webhook_secret = "github-concurrency-webhook-secret-#{context.suffix}"

    SecretStore.put(%{
      attrs.webhook_secret_reference => webhook_secret,
      attrs.app_private_key_reference => "github-concurrency-private-key-#{context.suffix}"
    })

    credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))

    context
    |> Map.put(:bound, bound)
    |> Map.put(:installation, bound.installation)
    |> Map.put(:credential_id, credential.credential_id)
    |> Map.put(:webhook_secret, webhook_secret)
  end

  defp bootstrap_context(label) do
    suffix = "#{label}-#{System.unique_integer([:positive])}"
    organization_slug = "github-concurrency-#{suffix}"
    owner_email = "github-concurrency-owner-#{suffix}@office-graph.local"

    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_name: "GitHub concurrency #{suffix}",
        organization_slug: organization_slug,
        workspace_name: "GitHub concurrency workspace #{suffix}",
        workspace_slug: "github-concurrency-workspace-#{suffix}",
        initiative_name: "GitHub concurrency initiative #{suffix}",
        initiative_slug: "github-concurrency-initiative-#{suffix}",
        owner_email: owner_email
      )

    %{
      bootstrap: bootstrap,
      suffix: suffix,
      organization_slug: organization_slug,
      owner_email: owner_email,
      service_email: "github-concurrency-service-#{suffix}@office-graph.local",
      webhook_email: "github-concurrency-webhook-#{suffix}@office-graph.local"
    }
  end

  defp binding_attrs(context) do
    %{
      idempotency_key: "github-concurrency-bind-#{context.suffix}",
      external_installation_id: System.unique_integer([:positive]),
      workspace_id: context.bootstrap.workspace.id,
      app_slug: "office-graph",
      account_login: "Un3qual",
      account_type: "organization",
      service_principal_email: context.service_email,
      webhook_principal_email: context.webhook_email,
      webhook_secret_reference: "test-secret://github/#{context.suffix}/webhook",
      app_private_key_reference: "test-secret://github/#{context.suffix}/private-key",
      permissions: [
        %{name: "checks", access_level: "write"},
        %{name: "pull_requests", access_level: "write"}
      ]
    }
  end

  defp reconciliation_request(context, object_type, object_id, delivery_id) do
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

  defp command_operation!(context, suffix, attrs) do
    {:ok, operation} =
      Operations.start_command(
        context.bootstrap.session,
        :github_review_reply,
        "github-concurrency-reply-#{context.suffix}-#{suffix}",
        attrs
      )

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

  defp webhook_payload(external_installation_id) do
    Jason.encode!(%{
      "action" => "opened",
      "installation" => %{"id" => external_installation_id},
      "pull_request" => %{"id" => 44}
    })
  end

  defp signed_headers(delivery_id, event, body, secret) do
    signature = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

    %{
      "x-github-delivery" => delivery_id,
      "x-github-event" => event,
      "x-hub-signature-256" => "sha256=#{signature}"
    }
  end

  defp reconciliation_snapshot(
         sequence,
         review_comment_node_id,
         title,
         pull_request_node_id \\ "PR_ordered"
       ) do
    %Adapter.ReconciliationSnapshot{
      provider_version: "v#{sequence}",
      provider_sequence: sequence,
      provider_updated_at: DateTime.add(~U[2026-07-28 12:00:00Z], sequence, :second),
      repository: %Adapter.RepositorySnapshot{
        node_id: "R_concurrency",
        database_id: 9_001,
        name: "office-graph",
        full_name: "Un3qual/office-graph",
        owner_login: "Un3qual",
        default_ref_name: "main",
        visibility: "private",
        url: "https://github.com/Un3qual/office-graph"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: pull_request_node_id,
        database_id: 9_002,
        number: 42,
        title: title,
        body: "Exercise separate-owner reconciliation.",
        state: "open",
        is_draft: false,
        author_label: "reviewer",
        url: "https://github.com/Un3qual/office-graph/pull/42"
      },
      review_threads: [],
      review_comments: [
        %Adapter.ReviewCommentSnapshot{
          node_id: review_comment_node_id,
          database_id: 9_003 + sequence,
          body: "Ordering comment #{sequence}",
          author_label: "review-bot",
          state: "published",
          published_at: DateTime.add(~U[2026-07-28 11:59:00Z], sequence, :second),
          url: "https://github.com/Un3qual/office-graph/pull/42#discussion-#{sequence}"
        }
      ],
      check_runs: []
    }
  end

  defp outbound_snapshot do
    %Adapter.ReconciliationSnapshot{
      provider_version: "v1",
      provider_sequence: 1,
      provider_updated_at: ~U[2026-07-28 13:00:00Z],
      repository: %Adapter.RepositorySnapshot{
        node_id: "R_concurrency",
        database_id: 9_101,
        name: "office-graph",
        full_name: "Un3qual/office-graph",
        owner_login: "Un3qual",
        default_ref_name: "main",
        visibility: "private",
        url: "https://github.com/Un3qual/office-graph"
      },
      pull_request: %Adapter.PullRequestSnapshot{
        node_id: "PR_concurrency",
        database_id: 9_102,
        number: 43,
        title: "Concurrent outbound actions",
        state: "open",
        is_draft: false,
        url: "https://github.com/Un3qual/office-graph/pull/43"
      },
      review_threads: [],
      review_comments: [
        %Adapter.ReviewCommentSnapshot{
          node_id: "PRRC_concurrency",
          database_id: 9_103,
          body: "Concurrent outbound review",
          author_label: "review-bot",
          state: "published",
          published_at: ~U[2026-07-28 12:59:00Z],
          url: "https://github.com/Un3qual/office-graph/pull/43#discussion-9103"
        }
      ],
      check_runs: []
    }
  end

  defp register_cleanup(context) do
    organization_id = context.bootstrap.organization.id

    on_exit(fn ->
      with_unboxed_connection(fn ->
        GitHubIntegrationCleanup.cleanup_scope!(organization_id)
        ConcurrencyCleanup.cleanup_bootstrap_scope!(context.organization_slug, context.owner_email)
        ConcurrencyCleanup.cleanup_owner_principal!(context.service_email)
        ConcurrencyCleanup.cleanup_owner_principal!(context.webhook_email)
      end)
    end)
  end
end
