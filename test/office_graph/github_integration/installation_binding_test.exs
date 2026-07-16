defmodule OfficeGraph.GitHubIntegration.InstallationBindingTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, GitHubIntegration, Repo}
  alias OfficeGraph.Authorization.RoleAssignment

  alias OfficeGraph.GitHubIntegration.{
    Installation,
    InstallationCredential,
    PermissionEntry,
    PermissionSnapshot,
    RecordLoaderTestAdapter
  }

  alias OfficeGraph.Identity.Principal
  alias OfficeGraph.Integrations.IntegrationCredential

  import OfficeGraph.SessionCaseHelpers

  test "authorized owners bind and replay an installation without storing secret values" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    attrs = binding_attrs(bootstrap, "authorized")

    assert {:ok, first} = GitHubIntegration.bind_installation(bootstrap.session, attrs)
    assert {:ok, replay} = GitHubIntegration.bind_installation(bootstrap.session, attrs)

    assert replay.operation.id == first.operation.id
    assert replay.installation.id == first.installation.id
    assert replay.permission_snapshot.id == first.permission_snapshot.id

    assert Enum.map(replay.permissions, &{&1.name, &1.access_level}) ==
             Enum.map(first.permissions, &{&1.name, &1.access_level})

    installation = first.installation
    assert installation.organization_id == bootstrap.organization.id
    assert installation.workspace_id == bootstrap.workspace.id
    assert installation.external_installation_id == attrs.external_installation_id
    assert installation.lifecycle_state == "active"

    service = Ash.get!(Principal, installation.service_principal_id, authorize?: false)
    webhook = Ash.get!(Principal, installation.webhook_principal_id, authorize?: false)
    assert service.kind == "service"
    assert service.status == "active"
    assert webhook.kind == "webhook"
    assert webhook.status == "active"

    assert Enum.map(first.permissions, &{&1.name, &1.access_level}) == [
             {"checks", "write"},
             {"pull_requests", "read"}
           ]

    assert Enum.sort(Enum.map(first.credentials, & &1.purpose)) == [
             "app_private_key",
             "webhook_secret"
           ]

    credential_ids = Enum.map(first.credentials, & &1.credential_id)

    credentials =
      Enum.map(credential_ids, &Ash.get!(IntegrationCredential, &1, authorize?: false))

    assert Enum.all?(credentials, &(&1.status == "active"))
    assert Enum.all?(credentials, &String.starts_with?(&1.secret_reference, "test-secret://"))
    refute inspect(first) =~ "actual-webhook-secret"
    refute inspect(first) =~ "actual-private-key"

    assert Repo.aggregate(Installation, :count) == 1
    assert Repo.aggregate(PermissionSnapshot, :count) == 1
    assert Repo.aggregate(PermissionEntry, :count) == 2
  end

  test "organization-scoped binding requires an organization-scoped capability grant" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    attrs = %{binding_attrs(bootstrap, "organization-scope") | workspace_id: nil}
    principal_count = Repo.aggregate(Principal, :count)
    role_assignment_count = Repo.aggregate(RoleAssignment, :count)

    assert {:error, :forbidden} = GitHubIntegration.bind_installation(bootstrap.session, attrs)
    assert Repo.aggregate(Installation, :count) == 0
    assert Repo.aggregate(Principal, :count) == principal_count
    assert Repo.aggregate(RoleAssignment, :count) == role_assignment_count
    assert Repo.aggregate(IntegrationCredential, :count) == 0
    assert Repo.aggregate(InstallationCredential, :count) == 0

    grant_organization_role_assignment!(bootstrap)

    assert {:ok, bound} = GitHubIntegration.bind_installation(bootstrap.session, attrs)
    assert bound.installation.workspace_id == nil
    assert Repo.aggregate(Installation, :count) == 1
  end

  test "installation lookup storage failures remain retryable during binding" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    attrs = binding_attrs(bootstrap, "lookup-unavailable")

    RecordLoaderTestAdapter.configure!(%{Installation => {:error, :database_unavailable}})

    assert {:error, :integration_storage_unavailable} =
             GitHubIntegration.bind_installation(bootstrap.session, attrs)

    assert Repo.aggregate(Installation, :count) == 0
  end

  test "binding rejects changed replay input, missing capability, and cross-tenant scope" do
    {:ok, first} = Foundation.bootstrap_local_owner([])

    {:ok, second} =
      Foundation.bootstrap_local_owner(
        organization_name: "Other integration organization",
        organization_slug: "other-integration-organization",
        workspace_name: "Other integration workspace",
        workspace_slug: "other-integration-workspace",
        initiative_name: "Other integration initiative",
        initiative_slug: "other-integration-initiative",
        owner_email: "other-integration-owner@office-graph.local"
      )

    attrs = binding_attrs(first, "isolation")
    assert {:ok, bound} = GitHubIntegration.bind_installation(first.session, attrs)

    changed = put_in(attrs.permissions, [%{name: "pull_requests", access_level: "write"}])

    assert {:error, {:command_idempotency_conflict, operation_id}} =
             GitHubIntegration.bind_installation(first.session, changed)

    assert operation_id == bound.operation.id

    no_capabilities = create_session_with_capabilities!(first, [], prefix: "github-bind-denied")
    denied_attrs = binding_attrs(first, "denied")

    assert {:error, :forbidden} =
             GitHubIntegration.bind_installation(no_capabilities, denied_attrs)

    cross_scope = %{binding_attrs(second, "cross-scope") | workspace_id: first.workspace.id}
    assert {:error, :forbidden} = GitHubIntegration.bind_installation(second.session, cross_scope)

    duplicate_provider_id = %{
      binding_attrs(second, "duplicate-provider")
      | external_installation_id: attrs.external_installation_id
    }

    assert {:error, :forbidden} =
             GitHubIntegration.bind_installation(second.session, duplicate_provider_id)

    assert Repo.aggregate(Installation, :count) == 1
  end

  test "installations in the same scope reuse credential metadata for shared references" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    shared = binding_attrs(bootstrap, "shared-first")

    second =
      bootstrap
      |> binding_attrs("shared-second")
      |> Map.put(:webhook_secret_reference, shared.webhook_secret_reference)
      |> Map.put(:app_private_key_reference, shared.app_private_key_reference)

    assert {:ok, first_binding} =
             GitHubIntegration.bind_installation(bootstrap.session, shared)

    assert {:ok, second_binding} =
             GitHubIntegration.bind_installation(bootstrap.session, second)

    first_credentials =
      Map.new(first_binding.credentials, &{&1.purpose, &1.credential_id})

    second_credentials =
      Map.new(second_binding.credentials, &{&1.purpose, &1.credential_id})

    assert second_credentials == first_credentials
    assert Repo.aggregate(IntegrationCredential, :count) == 2
  end

  test "secret references reject content outside one complete URI or environment reference" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    attrs =
      bootstrap
      |> binding_attrs("invalid-secret-reference")
      |> Map.put(
        :webhook_secret_reference,
        "test-secret://github/valid-prefix\nUNTRUSTED_SUFFIX"
      )

    assert {:error, {:invalid_field, :webhook_secret_reference}} =
             GitHubIntegration.bind_installation(bootstrap.session, attrs)

    assert Repo.aggregate(Installation, :count) == 0
  end

  test "concurrent external installation claims have one stable forbidden loser" do
    suffix = System.unique_integer([:positive])

    {:ok, first} =
      Foundation.bootstrap_local_owner(
        organization_name: "Installation race A #{suffix}",
        organization_slug: "installation-race-a-#{suffix}",
        workspace_name: "Installation race A workspace #{suffix}",
        workspace_slug: "installation-race-a-workspace-#{suffix}",
        initiative_name: "Installation race A initiative #{suffix}",
        initiative_slug: "installation-race-a-initiative-#{suffix}",
        owner_email: "installation-race-a-#{suffix}@office-graph.local"
      )

    {:ok, second} =
      Foundation.bootstrap_local_owner(
        organization_name: "Installation race B #{suffix}",
        organization_slug: "installation-race-b-#{suffix}",
        workspace_name: "Installation race B workspace #{suffix}",
        workspace_slug: "installation-race-b-workspace-#{suffix}",
        initiative_name: "Installation race B initiative #{suffix}",
        initiative_slug: "installation-race-b-initiative-#{suffix}",
        owner_email: "installation-race-b-#{suffix}@office-graph.local"
      )

    external_installation_id = System.unique_integer([:positive])

    requests = [
      {first,
       %{binding_attrs(first, "race-a") | external_installation_id: external_installation_id}},
      {second,
       %{binding_attrs(second, "race-b") | external_installation_id: external_installation_id}}
    ]

    results =
      requests
      |> Enum.map(fn {bootstrap, attrs} ->
        Task.async(fn -> GitHubIntegration.bind_installation(bootstrap.session, attrs) end)
      end)
      |> Task.await_many(10_000)

    assert Enum.count(results, &match?({:ok, _binding}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :forbidden})) == 1
    assert Repo.aggregate(Installation, :count) == 1
  end

  defp binding_attrs(bootstrap, label) do
    %{
      idempotency_key: "github-bind-#{label}",
      external_installation_id: System.unique_integer([:positive]),
      workspace_id: bootstrap.workspace.id,
      app_slug: "office-graph",
      account_login: "Un3qual",
      account_type: "organization",
      service_principal_email: "github-service-#{label}@office-graph.local",
      webhook_principal_email: "github-webhook-#{label}@office-graph.local",
      webhook_secret_reference: "test-secret://github/#{label}/webhook",
      app_private_key_reference: "test-secret://github/#{label}/private-key",
      permissions: [
        %{name: "pull_requests", access_level: "read"},
        %{name: "checks", access_level: "write"}
      ]
    }
  end
end
