defmodule OfficeGraph.EnterpriseIdentity.ConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  alias OfficeGraph.{Authorization, EnterpriseIdentity, Identity}

  alias OfficeGraph.EnterpriseIdentity.{
    Directory,
    DirectoryMembership,
    EnterpriseConnection
  }

  alias OfficeGraph.Identity.{ExternalIdentityLink, Principal}

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
              provider_identity_id: "idp_user_01",
              verified_email: bootstrap.principal.email,
              current_principal_id: bootstrap.principal.id,
              current_principal_origin: "reused"
            })
          end,
          fn ->
            Identity.reconcile_workos_sso_identity(
              %{
                subject: "connection_01:idp_user_01",
                idp_id: "idp_user_01",
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

  test "directory reconciliation revalidates a principal committed after its eligibility read" do
    email =
      "enterprise-concurrency-late-principal-#{System.unique_integer([:positive])}@example.test"

    provider_tenant = "workos-organization-#{System.unique_integer([:positive])}"
    gate = make_ref()
    parent = self()

    holder =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Ash.transact(Principal, fn ->
            principal =
              Ash.create!(
                Principal,
                %{email: email, kind: "system", status: "inactive"},
                action: :create,
                authorize?: false
              )

            send(parent, {gate, :principal_inserted})

            receive do
              {^gate, :commit_principal} -> principal
            end
          end)
        end)
      end)

    assert_receive {^gate, :principal_inserted}, 5_000

    reconciliation =
      Task.async(fn ->
        send(parent, {gate, :reconciliation_ready, self()})

        receive do
          {^gate, :reconcile} ->
            with_unboxed_connection(fn ->
              Identity.reconcile_directory_identity(%{
                provider_tenant: provider_tenant,
                subject: "directory_user_late_principal",
                provider_identity_id: "idp_user_late_principal",
                verified_email: email,
                current_principal_id: nil,
                current_principal_origin: nil
              })
            end)
        end
      end)

    assert_receive {^gate, :reconciliation_ready, reconciliation_pid}, 5_000

    Code.ensure_loaded!(OfficeGraph.Identity.Actions.ReconcileDirectoryIdentity)

    :erlang.trace_pattern(
      {OfficeGraph.Identity.Actions.ReconcileDirectoryIdentity, :locked_links_for_email, 1},
      [{:_, [], [{:return_trace}]}],
      [:local]
    )

    :erlang.trace(reconciliation_pid, true, [:call])
    send(reconciliation_pid, {gate, :reconcile})

    try do
      assert_receive {:trace, ^reconciliation_pid, :return_from,
                      {OfficeGraph.Identity.Actions.ReconcileDirectoryIdentity,
                       :locked_links_for_email, 1}, {:ok, []}},
                     5_000

      send(holder.pid, {gate, :commit_principal})
      assert {:ok, %Principal{kind: "system", status: "inactive"}} = Task.await(holder, 5_000)

      assert {:review, "ineligible_principal"} = Task.await(reconciliation, 5_000)
    after
      send(holder.pid, {gate, :commit_principal})

      :erlang.trace_pattern(
        {OfficeGraph.Identity.Actions.ReconcileDirectoryIdentity, :locked_links_for_email, 1},
        false,
        [:local]
      )

      Task.shutdown(holder, :brutal_kill)
      Task.shutdown(reconciliation, :brutal_kill)

      with_unboxed_connection(fn ->
        OfficeGraph.TestSupport.ConcurrencyCleanup.cleanup_owner_principal!(email)
      end)
    end
  end

  test "separate owners serialize equal-time membership events to one active fact" do
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

      assert Enum.all?(
               results,
               &match?({:ok, %{status: status}} when status in [:applied, :stale], &1)
             )

      assert Enum.any?(results, &match?({:ok, %{status: :applied}}, &1))

      active_membership =
        with_unboxed_connection(fn ->
          DirectoryMembership
          |> Ash.Query.filter(
            status == "active" and directory_user_id == ^context.user.id and
              directory_group_id == ^context.group.id
          )
          |> Ash.read_one!(authorize?: false)
        end)

      assert active_membership.provider_event_id == "membership-event-b"
    after
      cleanup(cleanup_attrs)
    end
  end

  test "deprovisioning and SSO reconciliation serialize on the principal" do
    {context, cleanup_attrs} = enterprise_context("deprovision-sso-race")
    created_user_email = "directory-created-#{System.unique_integer([:positive])}@example.test"

    try do
      {:ok, %{status: :applied, resource: directory_user}} =
        with_unboxed_connection(fn ->
          EnterpriseIdentity.apply_directory_event(
            context.directory.id,
            user_event(created_user_email, "directory_user_race"),
            context.operation.id
          )
        end)

      assert directory_user.principal_origin == "created"

      [deprovision_result, sso_result] =
        [
          fn ->
            EnterpriseIdentity.apply_directory_event(
              context.directory.id,
              user_event(
                created_user_email,
                "directory_user_race",
                "suspended",
                ~U[2026-07-29 21:00:00Z]
              ),
              context.operation.id
            )
          end,
          fn ->
            Identity.reconcile_workos_sso_identity(
              %{
                subject: "connection_race:idp_user_race",
                idp_id: "idp_user_race",
                verified_email: created_user_email
              },
              context.connection.provider_organization_id
            )
          end
        ]
        |> run_concurrently()

      assert {:ok, %{status: :applied}} = deprovision_result
      assert match?({:ok, _linked}, sso_result) or match?({:review, _reason}, sso_result)

      with_unboxed_connection(fn ->
        principal = Ash.get!(Principal, directory_user.principal_id, authorize?: false)

        active_sso_link? =
          ExternalIdentityLink
          |> Ash.Query.filter(
            principal_id == ^principal.id and provider == "workos_sso" and
              status == "active" and linking_state == "linked"
          )
          |> Ash.exists?(authorize?: false)

        refute principal.status == "disabled" and active_sso_link?
      end)
    after
      cleanup(Keyword.put(cleanup_attrs, :created_user_email, created_user_email))
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

        %{
          connection: connection,
          directory: directory,
          operation: operation,
          user: user,
          group: group
        }
      end)

    {context, Keyword.put(attrs, :webhook_email, webhook_email)}
  end

  defp user_event(
         email,
         provider_user_id \\ "directory_user_01",
         status \\ "active",
         provider_updated_at \\ ~U[2026-07-29 20:00:00Z]
       ) do
    %DirectoryEvent{
      provider_event_id:
        "user-event:#{provider_user_id}:#{status}:#{DateTime.to_iso8601(provider_updated_at)}",
      event_type: "dsync.user.created",
      directory_id: "bound-by-action",
      resource_kind: :user,
      action: :upsert,
      provider_occurred_at: provider_updated_at,
      data: %{
        provider_user_id: provider_user_id,
        idp_id: String.replace_prefix(provider_user_id, "directory_", "idp_"),
        email: email,
        first_name: nil,
        last_name: nil,
        status: status,
        provider_updated_at: provider_updated_at
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

      if created_user_email = attrs[:created_user_email] do
        OfficeGraph.TestSupport.ConcurrencyCleanup.cleanup_owner_principal!(created_user_email)
      end
    end)
  end
end
