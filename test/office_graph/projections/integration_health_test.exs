defmodule OfficeGraph.Projections.IntegrationHealthTest do
  use OfficeGraph.DataCase, async: false

  import OfficeGraph.SessionCaseHelpers

  alias OfficeGraph.{Foundation, GitHubIntegration, Operations, Projections, QueryCounter, Repo}

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    OutboundAction,
    RecordLoaderTestAdapter,
    SyncOutcome
  }

  test "health is bounded, safe, and contains no credential references or payloads" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-health",
        external_installation_id: System.unique_integer([:positive]),
        workspace_id: bootstrap.workspace.id,
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-health@office-graph.local",
        webhook_principal_email: "github-webhook-health@office-graph.local",
        webhook_secret_reference: "test-secret://github/health/webhook",
        app_private_key_reference: "test-secret://github/health/private-key",
        permissions: [
          %{name: "checks", access_level: "write"},
          %{name: "pull_requests", access_level: "write"}
        ]
      })

    {{:ok, health}, queries} =
      QueryCounter.count(fn ->
        Projections.integration_health(bootstrap.session, bound.installation.id, limit: 50)
      end)

    assert health.lifecycle == "active"
    assert health.permission_posture == "configured"
    assert health.credential_posture == "active"
    assert health.retryable_count == 0
    assert health.terminal_count == 0
    assert is_nil(health.remediation_code)

    serialized = inspect(health)
    refute serialized =~ "test-secret://"
    refute serialized =~ "private-key"
    refute serialized =~ "raw_archive"

    assert QueryCounter.source_count(queries, "github_installations") <= 1
    assert QueryCounter.source_count(queries, "github_permission_entries") <= 1
    assert QueryCounter.source_count(queries, "github_installation_credentials") <= 1
    assert QueryCounter.source_count(queries, "integration_credentials") <= 1
    assert QueryCounter.source_count(queries, "github_sync_outcomes") <= 3
    assert QueryCounter.source_count(queries, "github_outbound_actions") <= 2
  end

  test "unknown installation is non-enumerating" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:error, :forbidden} =
             Projections.integration_health(bootstrap.session, Ecto.UUID.generate())
  end

  test "installation lookup outages remain distinguishable from forbidden reads" do
    context = health_context("installation-lookup-unavailable")

    RecordLoaderTestAdapter.configure!(%{Installation => {:error, :database_unavailable}})

    assert {:error, :integration_storage_unavailable} =
             Projections.integration_health(
               context.bootstrap.session,
               context.installation.id
             )
  end

  test "organization-scoped health requires organization-scoped read authority" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    grant_organization_role_assignment!(bootstrap)

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-health-organization-scope",
        external_installation_id: System.unique_integer([:positive]),
        workspace_id: nil,
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-health-org@office-graph.local",
        webhook_principal_email: "github-webhook-health-org@office-graph.local",
        webhook_secret_reference: "test-secret://github/health/org/webhook",
        app_private_key_reference: "test-secret://github/health/org/private-key",
        permissions: [
          %{name: "checks", access_level: "write"},
          %{name: "pull_requests", access_level: "write"}
        ]
      })

    workspace_reader =
      create_session_with_capabilities!(bootstrap, ["skeleton.read"],
        prefix: "github-health-workspace-reader"
      )

    assert {:error, :forbidden} =
             Projections.integration_health(workspace_reader, bound.installation.id)
  end

  test "last success uses the successful transition time of a recovered outcome" do
    context = health_context("success-transition")

    outcome = create_outcome!(context, "recovered", "retryable", "provider_unavailable")
    Process.sleep(1)

    recovered =
      outcome
      |> Ash.Changeset.for_update(:record_result, %{
        state: "reconciled",
        failure_class: nil,
        failure_code: nil
      })
      |> Repo.ash_update!()

    assert DateTime.compare(recovered.updated_at, recovered.inserted_at) == :gt

    assert {:ok, health} =
             Projections.integration_health(
               context.bootstrap.session,
               context.installation.id
             )

    assert health.last_success_at == recovered.updated_at
  end

  test "failure summaries apply the display limit after filtering successful outcomes" do
    context = health_context("failure-filtering")

    _failure = create_outcome!(context, "failure", "terminal", "invalid_credential")

    for sequence <- 1..3 do
      Process.sleep(1)
      create_outcome!(context, "success-#{sequence}", "reconciled", nil)
    end

    assert {:ok, health} =
             Projections.integration_health(
               context.bootstrap.session,
               context.installation.id,
               limit: 2
             )

    assert health.retryable_count == 0
    assert health.terminal_count == 1
    assert Enum.map(health.recent_failures, & &1.code) == ["invalid_credential"]
    assert health.remediation_code == "rotate_credentials"
  end

  test "headline failure counts include records outside the recent display limit" do
    context = health_context("complete-failure-counts")

    for sequence <- 1..3 do
      create_outcome!(
        context,
        "retryable-#{sequence}",
        "retryable",
        "provider_unavailable"
      )
    end

    for sequence <- 1..2 do
      create_action!(context, "terminal-#{sequence}", "terminal", "invalid_credential")
    end

    assert {:ok, health} =
             Projections.integration_health(
               context.bootstrap.session,
               context.installation.id,
               limit: 2
             )

    assert health.retryable_count == 3
    assert health.terminal_count == 2
    assert length(health.recent_failures) == 2
  end

  test "health reports incomplete required permission grants as insufficient" do
    incomplete_permissions = [
      {"unrelated-read", [%{name: "issues", access_level: "read"}]},
      {"pull-requests-only", [%{name: "pull_requests", access_level: "write"}]},
      {"checks-only", [%{name: "checks", access_level: "write"}]},
      {"pull-requests-read",
       [
         %{name: "checks", access_level: "write"},
         %{name: "pull_requests", access_level: "read"}
       ]}
    ]

    Enum.each(incomplete_permissions, fn {label, permissions} ->
      context = health_context("permissions-#{label}", permissions)

      assert {:ok, health} =
               Projections.integration_health(
                 context.bootstrap.session,
                 context.installation.id
               )

      assert health.permission_posture == "insufficient"
      assert health.remediation_code == "reauthorize_installation"
    end)
  end

  defp health_context(
         label,
         permissions \\ [
           %{name: "checks", access_level: "write"},
           %{name: "pull_requests", access_level: "write"}
         ]
       ) do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    private_key_reference = "test-secret://github/health/#{label}/private-key"

    {:ok, bound} =
      GitHubIntegration.bind_installation(bootstrap.session, %{
        idempotency_key: "bind-health-#{label}",
        external_installation_id: System.unique_integer([:positive]),
        workspace_id: bootstrap.workspace.id,
        app_slug: "office-graph",
        account_login: "Un3qual",
        account_type: "organization",
        service_principal_email: "github-service-health-#{label}@office-graph.local",
        webhook_principal_email: "github-webhook-health-#{label}@office-graph.local",
        webhook_secret_reference: "test-secret://github/health/#{label}/webhook",
        app_private_key_reference: private_key_reference,
        permissions: permissions
      })

    credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))

    %{
      bootstrap: bootstrap,
      installation: bound.installation,
      credential_id: credential.credential_id
    }
  end

  defp create_outcome!(context, label, state, failure_code) do
    operation = sync_operation!(context, label)

    Repo.ash_create!(SyncOutcome, %{
      id: Ecto.UUID.generate(),
      installation_id: context.installation.id,
      operation_id: operation.id,
      object_type: "pull_request",
      object_id: "PR_health_#{label}",
      delivery_id: "delivery-health-#{label}",
      state: state,
      signal_ids: [],
      failure_class: if(failure_code, do: state),
      failure_code: failure_code
    })
  end

  defp create_action!(context, label, state, failure_code) do
    operation = sync_operation!(context, "action-#{label}")

    OutboundAction
    |> Repo.ash_create!(%{
      id: Ecto.UUID.generate(),
      installation_id: context.installation.id,
      operation_id: operation.id,
      principal_id: context.installation.service_principal_id,
      organization_id: context.bootstrap.organization.id,
      workspace_id: context.bootstrap.workspace.id,
      action_kind: "review_reply",
      target_type: "review_comment",
      target_id: Ecto.UUID.generate(),
      expected_provider_version: "v1",
      input: %{}
    })
    |> Ash.Changeset.for_update(:record_result, %{
      state: state,
      failure_class: state,
      failure_code: failure_code,
      attempted_at: DateTime.utc_now()
    })
    |> Repo.ash_update!()
  end

  defp sync_operation!(context, label) do
    {:ok, request} =
      Operations.new_system_operation_request(%{
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.bootstrap.workspace.id,
        principal_id: context.installation.service_principal_id,
        action: :integration_reconcile,
        authority_basis: "github_installation:#{context.installation.id}",
        causation_key: "github_delivery:health-#{label}",
        idempotency_scope: "github:object",
        idempotency_key: "health:#{label}",
        credential_id: context.credential_id
      })

    {:ok, operation} = Operations.start_system_operation(request)
    operation
  end
end
