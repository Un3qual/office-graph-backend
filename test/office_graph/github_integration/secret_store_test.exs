defmodule OfficeGraph.GitHubIntegration.SecretStoreTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration}
  alias OfficeGraph.GitHubIntegration.{RecordLoaderTestAdapter, SecretStore}
  alias OfficeGraph.GitHubIntegration.SecretStore.{Environment, TestAdapter}
  alias OfficeGraph.Integrations.IntegrationCredential

  test "resolves opaque credential references only within the bound tenant" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    attrs = binding_attrs(bootstrap)
    assert {:ok, bound} = GitHubIntegration.bind_installation(bootstrap.session, attrs)

    webhook_binding = Enum.find(bound.credentials, &(&1.purpose == "webhook_secret"))

    TestAdapter.put(%{attrs.webhook_secret_reference => "actual-webhook-secret"})

    assert {:ok, "actual-webhook-secret"} =
             SecretStore.resolve(
               webhook_binding.credential_id,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id
               },
               TestAdapter
             )

    assert {:error, :forbidden} =
             SecretStore.resolve(
               webhook_binding.credential_id,
               %{
                 organization_id: Ecto.UUID.generate(),
                 workspace_id: bootstrap.workspace.id
               },
               TestAdapter
             )

    TestAdapter.put(%{})

    assert {:error, :secret_not_found} =
             SecretStore.resolve(
               webhook_binding.credential_id,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id
               },
               TestAdapter
             )
  end

  test "environment adapter resolves only explicitly named environment references" do
    variable = "OFFICE_GRAPH_GITHUB_SECRET_TEST_#{System.unique_integer([:positive])}"
    System.put_env(variable, "environment-secret")
    on_exit(fn -> System.delete_env(variable) end)

    assert {:ok, "environment-secret"} = Environment.fetch("env:#{variable}", %{})
    assert {:error, :invalid_secret_reference} = Environment.fetch(variable, %{})
    assert {:error, :invalid_secret_reference} = Environment.fetch("env:../unsafe", %{})
  end

  test "credential metadata lookup outages remain distinguishable from secret-store outages" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    attrs = binding_attrs(bootstrap)
    assert {:ok, bound} = GitHubIntegration.bind_installation(bootstrap.session, attrs)

    credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))
    TestAdapter.put(%{attrs.app_private_key_reference => "private-key"})

    RecordLoaderTestAdapter.configure!(%{
      IntegrationCredential => {:error, :database_unavailable}
    })

    assert {:error, :integration_storage_unavailable} =
             SecretStore.resolve(
               credential.credential_id,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id
               },
               TestAdapter
             )
  end

  defp binding_attrs(bootstrap) do
    %{
      idempotency_key: "github-bind-secret-store",
      external_installation_id: System.unique_integer([:positive]),
      workspace_id: bootstrap.workspace.id,
      app_slug: "office-graph",
      account_login: "Un3qual",
      account_type: "organization",
      service_principal_email: "github-service-secret-store@office-graph.local",
      webhook_principal_email: "github-webhook-secret-store@office-graph.local",
      webhook_secret_reference: "test-secret://github/secret-store/webhook",
      app_private_key_reference: "test-secret://github/secret-store/private-key",
      permissions: [%{name: "pull_requests", access_level: "read"}]
    }
  end
end
