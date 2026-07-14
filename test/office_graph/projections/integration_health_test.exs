defmodule OfficeGraph.Projections.IntegrationHealthTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration, Projections, QueryCounter}

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
    assert QueryCounter.source_count(queries, "github_sync_outcomes") <= 2
    assert QueryCounter.source_count(queries, "github_outbound_actions") <= 1
  end

  test "unknown installation is non-enumerating" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:error, :forbidden} =
             Projections.integration_health(bootstrap.session, Ecto.UUID.generate())
  end
end
