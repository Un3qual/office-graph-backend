defmodule OfficeGraph.EnterpriseIdentity.ConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  alias OfficeGraph.{Authorization, EnterpriseIdentity, Identity}

  alias OfficeGraph.EnterpriseIdentity.{
    Directory,
    DirectoryMembership,
    EnterpriseConnection
  }

  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.DirectoryEvent

  require Ash.Query

  test "separate owners serialize directory-first and SSO-first identity reconciliation" do
    {bootstrap, cleanup_attrs} = bootstrap("identity-race")
    provider_tenant = "workos-organization-#{System.unique_integer([:positive])}"

    try do
      results =
        [
          fn ->
            Identity.reconcile_directory_identity(%{
              provider_tenant: provider_tenant,
              subject: "directory_user_01",
              verified_email: bootstrap.principal.email,
              current_principal_id: bootstrap.principal.id,
              current_principal_origin: "reused"
            })
          end,
          fn ->
            Identity.reconcile_workos_sso_identity(
              %{
                subject: "connection_01:idp_user_01",
                verified_email: bootstrap.principal.email
              },
              provider_tenant
            )
          end
        ]
        |> run_concurrently()

      assert Enum.all?(results, &match?({:ok, _linked}, &1))

      assert results
             |> Enum.map(fn {:ok, linked} -> linked.principal.id end)
             |> Enum.uniq() == [bootstrap.principal.id]
    after
      cleanup(cleanup_attrs)
    end
  end

  test "separate owners collapse duplicate membership events to one active fact" do
    {context, cleanup_attrs} = enterprise_context("membership-race")
    timestamp = ~U[2026-07-29 20:00:00Z]

    try do
      results =
        ["membership-event-a", "membership-event-b"]
        |> Enum.map(fn event_id ->
          fn ->
            EnterpriseIdentity.apply_directory_event(
              context.directory.id,
              membership_event(event_id, timestamp),
              context.operation.id
            )
          end
        end)
        |> run_concurrently()

      assert Enum.count(results, &match?({:ok, %{status: :applied}}, &1)) == 1
      assert Enum.count(results, &match?({:ok, %{status: :stale}}, &1)) == 1

      membership_count =
        with_unboxed_connection(fn ->
          DirectoryMembership
          |> Ash.Query.filter(
            status == "active" and directory_user_id == ^context.user.id and
              directory_group_id == ^context.group.id
          )
          |> Ash.count!(authorize?: false)
        end)

      assert membership_count == 1
    after
      cleanup(cleanup_attrs)
    end
  end

  defp bootstrap(label) do
    suffix = System.unique_integer([:positive])

    attrs = [
      organization_slug: "enterprise-concurrency-#{label}-#{suffix}",
      workspace_slug: "enterprise-concurrency-workspace-#{label}-#{suffix}",
      initiative_slug: "enterprise-concurrency-initiative-#{label}-#{suffix}",
      owner_email: "enterprise-concurrency-#{label}-#{suffix}@example.test"
    ]

    bootstrap =
      with_unboxed_connection(fn ->
        {:ok, bootstrap} = Foundation.bootstrap_local_owner(attrs)
        bootstrap
      end)

    {bootstrap, attrs}
  end

  defp enterprise_context(label) do
    {bootstrap, attrs} = bootstrap(label)
    suffix = System.unique_integer([:positive])
    webhook_email = "enterprise-concurrency-webhook-#{suffix}@office-graph.local"

    context =
      with_unboxed_connection(fn ->
        {:ok, webhook_principal} = Identity.ensure_system_principal(webhook_email, "webhook")

        :ok =
          Authorization.ensure_system_role(
            webhook_principal,
            %{
              organization_id: bootstrap.organization.id,
              workspace_id: bootstrap.workspace.id
            },
            [:provider_webhook_receive]
          )

        {:ok, request} =
          Operations.new_system_operation_request(%{
            organization_id: bootstrap.organization.id,
            workspace_id: bootstrap.workspace.id,
            principal_id: webhook_principal.id,
            action: :provider_webhook_receive,
            authority_basis: "workos:concurrency:#{suffix}",
            causation_key: "workos:concurrency:#{suffix}",
            idempotency_scope: "workos:concurrency",
            idempotency_key: Integer.to_string(suffix)
          })

        {:ok, operation} = Operations.start_system_operation(request)

        connection =
          Ash.create!(
            EnterpriseConnection,
            %{
              organization_id: bootstrap.organization.id,
              workspace_id: bootstrap.workspace.id,
              webhook_principal_id: webhook_principal.id,
              operation_id: operation.id,
              provider: "workos",
              provider_organization_id: "workos-organization-#{suffix}",
              directory_requirement: "required",
              status: "active"
            },
            action: :create,
            authorize?: false
          )

        directory =
          Ash.create!(
            Directory,
            %{
              connection_id: connection.id,
              operation_id: operation.id,
              provider_directory_id: "workos-directory-#{suffix}",
              status: "active",
              provider_updated_at: ~U[2026-07-29 19:00:00Z]
            },
            action: :create,
            authorize?: false
          )

        {:ok, %{status: :applied, resource: user}} =
          EnterpriseIdentity.apply_directory_event(
            directory.id,
            user_event(bootstrap.principal.email),
            operation.id
          )

        {:ok, %{status: :applied, resource: group}} =
          EnterpriseIdentity.apply_directory_event(
            directory.id,
            group_event(),
            operation.id
          )

        %{directory: directory, operation: operation, user: user, group: group}
      end)

    {context, Keyword.put(attrs, :webhook_email, webhook_email)}
  end

  defp user_event(email) do
    %DirectoryEvent{
      provider_event_id: "user-event",
      event_type: "dsync.user.created",
      directory_id: "bound-by-action",
      resource_kind: :user,
      action: :upsert,
      provider_occurred_at: ~U[2026-07-29 20:00:00Z],
      data: %{
        provider_user_id: "directory_user_01",
        idp_id: "idp_user_01",
        email: email,
        first_name: nil,
        last_name: nil,
        status: "active",
        provider_updated_at: ~U[2026-07-29 20:00:00Z]
      }
    }
  end

  defp group_event do
    %DirectoryEvent{
      provider_event_id: "group-event",
      event_type: "dsync.group.created",
      directory_id: "bound-by-action",
      resource_kind: :group,
      action: :upsert,
      provider_occurred_at: ~U[2026-07-29 20:00:00Z],
      data: %{
        provider_group_id: "directory_group_01",
        name: "Engineering",
        status: "active",
        provider_updated_at: ~U[2026-07-29 20:00:00Z]
      }
    }
  end

  defp membership_event(event_id, timestamp) do
    %DirectoryEvent{
      provider_event_id: event_id,
      event_type: "dsync.group.user_added",
      directory_id: "bound-by-action",
      resource_kind: :membership,
      action: :add,
      provider_occurred_at: timestamp,
      data: %{
        provider_group_id: "directory_group_01",
        provider_user_id: "directory_user_01",
        status: "active",
        provider_updated_at: timestamp
      }
    }
  end

  defp cleanup(attrs) do
    with_unboxed_connection(fn ->
      cleanup_bootstrap_scope!(attrs[:organization_slug], attrs[:owner_email])

      if webhook_email = attrs[:webhook_email] do
        OfficeGraph.TestSupport.ConcurrencyCleanup.cleanup_owner_principal!(webhook_email)
      end
    end)
  end
end
