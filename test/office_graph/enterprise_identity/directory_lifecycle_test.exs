defmodule OfficeGraph.EnterpriseIdentity.DirectoryLifecycleTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, EnterpriseIdentity, Foundation, Identity, Operations}

  alias OfficeGraph.EnterpriseIdentity.{
    Directory,
    DirectoryGroup,
    DirectoryMembership,
    DirectoryUser,
    EnterpriseConnection,
    ExternalGroupRoleMapping
  }

  alias OfficeGraph.Authorization.Role
  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.DirectoryEvent
  alias OfficeGraph.Identity.{ExternalIdentityLink, Principal}
  alias OfficeGraph.QueryCounter

  require Ash.Query

  test "user synchronization provisions one principal and rejects stale updates" do
    context = enterprise_context("user-lifecycle")
    initial_time = ~U[2026-07-29 20:00:00Z]

    assert {:ok, %{status: :applied, resource: %DirectoryUser{} = user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(initial_time, %{email: " Person@Example.TEST "}),
               context.operation.id
             )

    assert user.email == "person@example.test"
    assert user.status == "active"
    assert user.principal_origin == "created"
    assert is_binary(user.principal_id)
    assert is_binary(user.external_identity_link_id)

    principal = Ash.get!(Principal, user.principal_id, authorize?: false)
    link = Ash.get!(ExternalIdentityLink, user.external_identity_link_id, authorize?: false)

    assert principal.email == "person@example.test"
    assert principal.kind == "human"
    assert principal.status == "active"
    assert link.principal_id == principal.id
    assert link.provider == "workos_directory"
    assert link.provider_tenant == context.connection.provider_organization_id
    assert link.subject == "directory_user_01"
    assert link.status == "active"

    newer_time = DateTime.add(initial_time, 120, :second)

    assert {:ok, %{status: :applied, resource: updated}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(newer_time, %{first_name: "Ada", last_name: "Lovelace"}),
               context.operation.id
             )

    assert updated.id == user.id
    assert updated.first_name == "Ada"
    assert updated.last_name == "Lovelace"

    assert {:ok, %{status: :stale, resource: stale_preserved}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(DateTime.add(initial_time, 30, :second), %{first_name: "Older"}),
               context.operation.id
             )

    assert stale_preserved.id == user.id
    assert stale_preserved.first_name == "Ada"
    assert DateTime.compare(stale_preserved.provider_updated_at, newer_time) == :eq
  end

  test "group membership removal and restore retain history with one active fact" do
    context = enterprise_context("membership-lifecycle")
    initial_time = ~U[2026-07-29 20:00:00Z]

    assert {:ok, %{resource: %DirectoryUser{} = user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(initial_time),
               context.operation.id
             )

    assert {:ok, %{resource: %DirectoryGroup{} = group}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               group_event(initial_time),
               context.operation.id
             )

    assert {:ok, %{status: :applied, resource: first_membership}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               membership_event(initial_time, "active"),
               context.operation.id
             )

    assert first_membership.status == "active"

    removed_time = DateTime.add(initial_time, 60, :second)

    assert {:ok, %{status: :applied, resource: removed}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               membership_event(removed_time, "removed"),
               context.operation.id
             )

    assert removed.id == first_membership.id
    assert removed.status == "removed"
    assert is_nil(removed.active_identity_slot)
    assert DateTime.compare(removed.removed_at, removed_time) == :eq

    restored_time = DateTime.add(initial_time, 120, :second)

    assert {:ok, %{status: :applied, resource: restored}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               membership_event(restored_time, "active"),
               context.operation.id
             )

    assert restored.id != first_membership.id
    assert restored.status == "active"
    assert restored.active_identity_slot == "active"

    memberships =
      DirectoryMembership
      |> Ash.Query.filter(directory_user_id == ^user.id and directory_group_id == ^group.id)
      |> Ash.Query.sort(provider_updated_at: :asc)
      |> Ash.read!(authorize?: false)

    assert Enum.map(memberships, & &1.status) == ["removed", "active"]
    assert Enum.count(memberships, &(&1.active_identity_slot == "active")) == 1
  end

  test "directory deprovisioning disables WorkOS identities and a directory-created principal" do
    context = enterprise_context("deprovision")
    active_time = ~U[2026-07-29 20:00:00Z]

    assert {:ok, %{resource: %DirectoryUser{} = user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(active_time),
               context.operation.id
             )

    sso_link =
      Ash.create!(
        ExternalIdentityLink,
        %{
          principal_id: user.principal_id,
          provider: "workos_sso",
          provider_tenant: context.connection.provider_organization_id,
          subject: "connection_01:idp_user_01",
          verified_email: user.email,
          status: "active",
          linking_state: "linked",
          first_linked_at: active_time
        },
        action: :create,
        authorize?: false
      )

    deleted_time = DateTime.add(active_time, 60, :second)

    assert {:ok, %{status: :applied, resource: deleted}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(deleted_time, %{status: "deleted"}),
               context.operation.id
             )

    assert deleted.status == "deleted"

    directory_link =
      Ash.get!(ExternalIdentityLink, user.external_identity_link_id, authorize?: false)

    sso_link = Ash.get!(ExternalIdentityLink, sso_link.id, authorize?: false)
    principal = Ash.get!(Principal, user.principal_id, authorize?: false)

    assert directory_link.status == "disabled"
    assert sso_link.status == "disabled"
    assert principal.status == "disabled"
  end

  test "ambiguous normalized principals produce deterministic review state" do
    context = enterprise_context("ambiguous")
    email = "ambiguous@example.test"

    for stored_email <- [String.upcase(email), " #{email} "] do
      Ash.create!(
        Principal,
        %{email: stored_email, kind: "human", status: "active"},
        action: :create,
        authorize?: false
      )
    end

    assert {:ok, %{status: :review_required, resource: user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(~U[2026-07-29 20:00:00Z], %{email: email}),
               context.operation.id
             )

    assert user.status == "review_required"
    assert user.review_reason == "ambiguous_verified_identifier"
    assert is_nil(user.principal_id)
    assert is_nil(user.external_identity_link_id)
  end

  test "existing email links without a compatible principal use the conflict review reason" do
    context = enterprise_context("incompatible-email-link")
    email = "linked-conflict@example.test"

    incompatible_principal =
      Ash.create!(
        Principal,
        %{
          email: "different-#{email}",
          kind: "human",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    Ash.create!(
      ExternalIdentityLink,
      %{
        principal_id: incompatible_principal.id,
        provider: "oidc",
        provider_tenant: "https://identity.example.test",
        subject: unique("incompatible-subject"),
        verified_email: email,
        status: "active",
        linking_state: "linked",
        first_linked_at: ~U[2026-07-29 19:00:00Z]
      },
      action: :create,
      authorize?: false
    )

    assert {:ok, %{status: :review_required, resource: user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(~U[2026-07-29 20:00:00Z], %{email: email}),
               context.operation.id
             )

    assert user.review_reason == "verified_identifier_conflict"
    assert is_nil(user.principal_id)
    assert is_nil(user.external_identity_link_id)
  end

  test "active group mappings contribute exact live authorization facts" do
    context = enterprise_context("mapped-authorization")
    event_time = ~U[2026-07-29 20:00:00Z]

    {:ok, %{resource: user}} =
      EnterpriseIdentity.apply_directory_event(
        context.directory.id,
        user_event(event_time),
        context.operation.id
      )

    {:ok, %{resource: group}} =
      EnterpriseIdentity.apply_directory_event(
        context.directory.id,
        group_event(event_time),
        context.operation.id
      )

    {:ok, %{resource: membership}} =
      EnterpriseIdentity.apply_directory_event(
        context.directory.id,
        membership_event(event_time, "active"),
        context.operation.id
      )

    role =
      Role
      |> Ash.Query.filter(
        organization_id == ^context.bootstrap.organization.id and key == "owner"
      )
      |> Ash.read_one!(authorize?: false)

    mapping =
      Ash.create!(
        ExternalGroupRoleMapping,
        %{
          directory_group_id: group.id,
          role_id: role.id,
          organization_id: context.bootstrap.organization.id,
          workspace_id: context.bootstrap.workspace.id,
          operation_id: context.operation.id,
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    scope = %{
      organization_id: context.bootstrap.organization.id,
      workspace_id: context.bootstrap.workspace.id
    }

    assert {:ok, ^scope} = Authorization.resolve_login_scope(user.principal_id)

    {authorization_result, queries} =
      QueryCounter.count(fn ->
        Authorization.authorize_principal(
          user.principal_id,
          scope.organization_id,
          scope.workspace_id,
          :skeleton_read
        )
      end)

    assert :ok = authorization_result
    assert QueryCounter.source_count(queries, "enterprise_directory_memberships") == 1
    assert QueryCounter.source_count(queries, "external_group_role_mappings") == 1

    mapping
    |> Ash.Changeset.for_update(:set_lifecycle, %{
      status: "disabled",
      disabled_at: DateTime.utc_now()
    })
    |> Ash.update!(authorize?: false)

    assert {:error, :no_login_scope} =
             Authorization.resolve_login_scope(user.principal_id)

    assert {:error, :forbidden} =
             Authorization.authorize_principal(
               user.principal_id,
               scope.organization_id,
               scope.workspace_id,
               :skeleton_read
             )

    assert membership.status == "active"
  end

  test "organization-wide group mappings provide organization login scope and workspace authority" do
    fixture = mapped_authorization_context("organization-wide-mapping")

    fixture.mapping
    |> Ash.Changeset.for_update(:set_lifecycle, %{
      status: "disabled",
      disabled_at: DateTime.utc_now()
    })
    |> Ash.update!(authorize?: false)

    organization_mapping =
      Ash.create!(
        ExternalGroupRoleMapping,
        %{
          directory_group_id: fixture.group.id,
          role_id: fixture.mapping.role_id,
          organization_id: fixture.scope.organization_id,
          workspace_id: nil,
          operation_id: fixture.mapping.operation_id,
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    assert {:ok,
            %{
              organization_id: organization_id,
              workspace_id: nil
            }} = Authorization.resolve_login_scope(fixture.user.principal_id)

    assert organization_id == fixture.scope.organization_id

    assert :ok =
             Authorization.authorize_principal(
               fixture.user.principal_id,
               fixture.scope.organization_id,
               fixture.scope.workspace_id,
               :skeleton_read
             )

    assert organization_mapping.workspace_id == nil
  end

  test "every inactive enterprise fact layer removes mapped authority on the next read" do
    for layer <- [:connection, :directory, :user, :group, :membership, :mapping] do
      fixture = mapped_authorization_context("inactive-#{layer}")

      assert :ok =
               Authorization.authorize_principal(
                 fixture.user.principal_id,
                 fixture.scope.organization_id,
                 fixture.scope.workspace_id,
                 :skeleton_read
               )

      disable_authorization_layer(fixture, layer)

      assert {:error, :no_login_scope} =
               Authorization.resolve_login_scope(fixture.user.principal_id)

      assert {:error, :forbidden} =
               Authorization.authorize_principal(
                 fixture.user.principal_id,
                 fixture.scope.organization_id,
                 fixture.scope.workspace_id,
                 :skeleton_read
               )
    end
  end

  test "connection and mapping management require current scoped authority and operations" do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_slug: unique("management-organization"),
        workspace_slug: unique("management-workspace"),
        initiative_slug: unique("management-initiative"),
        owner_email: "#{unique("management-owner")}@example.test"
      )

    {:ok, webhook_principal} =
      Identity.ensure_system_principal(
        "#{unique("management-webhook")}@office-graph.local",
        "webhook"
      )

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :enterprise_identity_manage)

    assert {:ok, connection} =
             EnterpriseIdentity.create_connection(bootstrap.session, operation, %{
               webhook_principal_id: webhook_principal.id,
               provider: "workos",
               provider_organization_id: unique("managed-workos-organization"),
               directory_requirement: "required",
               status: "active"
             })

    directory =
      Ash.create!(
        Directory,
        %{
          connection_id: connection.id,
          operation_id: operation.id,
          provider_directory_id: unique("managed-directory"),
          status: "active",
          provider_updated_at: ~U[2026-07-29 19:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    group =
      Ash.create!(
        DirectoryGroup,
        %{
          directory_id: directory.id,
          provider_group_id: unique("managed-group"),
          name: "Managed Engineering",
          status: "active",
          provider_updated_at: ~U[2026-07-29 20:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    role =
      Role
      |> Ash.Query.filter(organization_id == ^bootstrap.organization.id and key == "owner")
      |> Ash.read_one!(authorize?: false)

    assert {:ok, mapping} =
             EnterpriseIdentity.create_group_role_mapping(
               bootstrap.session,
               operation,
               %{
                 directory_group_id: group.id,
                 role_id: role.id,
                 status: "active"
               }
             )

    assert mapping.operation_id == operation.id
    assert mapping.organization_id == bootstrap.organization.id
    assert mapping.workspace_id == bootstrap.workspace.id

    assert {:ok, disabled_mapping} =
             EnterpriseIdentity.set_group_role_mapping_lifecycle(
               bootstrap.session,
               operation,
               mapping.id,
               %{status: "disabled", disabled_at: DateTime.utc_now()}
             )

    assert disabled_mapping.status == "disabled"

    forged_session = %{bootstrap.session | organization_id: Ecto.UUID.generate()}

    assert {:error, :forbidden} =
             EnterpriseIdentity.set_connection_lifecycle(
               forged_session,
               operation,
               connection.id,
               %{status: "disabled"}
             )
  end

  defp enterprise_context(label) do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_slug: unique("#{label}-organization"),
        workspace_slug: unique("#{label}-workspace"),
        initiative_slug: unique("#{label}-initiative"),
        owner_email: "#{unique(label)}@example.test"
      )

    {:ok, webhook_principal} =
      Identity.ensure_system_principal(
        "#{unique("#{label}-webhook")}@office-graph.local",
        "webhook"
      )

    assert :ok =
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
        authority_basis: "workos:test:#{label}",
        causation_key: "workos:test:#{label}",
        idempotency_scope: "workos:test",
        idempotency_key: label
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
          provider_organization_id: unique("workos-organization"),
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
          provider_directory_id: unique("workos-directory"),
          status: "active",
          provider_updated_at: ~U[2026-07-29 19:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    %{
      bootstrap: bootstrap,
      connection: connection,
      directory: directory,
      operation: operation,
      webhook_principal: webhook_principal
    }
  end

  defp mapped_authorization_context(label) do
    context = enterprise_context(label)
    event_time = ~U[2026-07-29 20:00:00Z]

    {:ok, %{resource: user}} =
      EnterpriseIdentity.apply_directory_event(
        context.directory.id,
        user_event(event_time),
        context.operation.id
      )

    {:ok, %{resource: group}} =
      EnterpriseIdentity.apply_directory_event(
        context.directory.id,
        group_event(event_time),
        context.operation.id
      )

    {:ok, %{resource: membership}} =
      EnterpriseIdentity.apply_directory_event(
        context.directory.id,
        membership_event(event_time, "active"),
        context.operation.id
      )

    role =
      Role
      |> Ash.Query.filter(
        organization_id == ^context.bootstrap.organization.id and key == "owner"
      )
      |> Ash.read_one!(authorize?: false)

    mapping =
      Ash.create!(
        ExternalGroupRoleMapping,
        %{
          directory_group_id: group.id,
          role_id: role.id,
          organization_id: context.bootstrap.organization.id,
          workspace_id: context.bootstrap.workspace.id,
          operation_id: context.operation.id,
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    Map.merge(context, %{
      user: user,
      group: group,
      membership: membership,
      mapping: mapping,
      scope: %{
        organization_id: context.bootstrap.organization.id,
        workspace_id: context.bootstrap.workspace.id
      }
    })
  end

  defp disable_authorization_layer(fixture, :connection) do
    fixture.connection
    |> Ash.Changeset.for_update(:set_lifecycle, %{status: "disabled"})
    |> Ash.update!(authorize?: false)
  end

  defp disable_authorization_layer(fixture, :directory) do
    fixture.directory
    |> Ash.Changeset.for_update(:set_lifecycle, %{
      status: "disabled",
      provider_updated_at: ~U[2026-07-29 21:00:00Z]
    })
    |> Ash.update!(authorize?: false)
  end

  defp disable_authorization_layer(fixture, :user) do
    fixture.user
    |> Ash.Changeset.for_update(:synchronize, %{
      status: "suspended",
      provider_updated_at: ~U[2026-07-29 21:00:00Z]
    })
    |> Ash.update!(authorize?: false)
  end

  defp disable_authorization_layer(fixture, :group) do
    fixture.group
    |> Ash.Changeset.for_update(:synchronize, %{
      status: "deleted",
      provider_updated_at: ~U[2026-07-29 21:00:00Z]
    })
    |> Ash.update!(authorize?: false)
  end

  defp disable_authorization_layer(fixture, :membership) do
    fixture.membership
    |> Ash.Changeset.for_update(:set_lifecycle, %{
      status: "removed",
      removed_at: ~U[2026-07-29 21:00:00Z],
      provider_updated_at: ~U[2026-07-29 21:00:00Z]
    })
    |> Ash.update!(authorize?: false)
  end

  defp disable_authorization_layer(fixture, :mapping) do
    fixture.mapping
    |> Ash.Changeset.for_update(:set_lifecycle, %{
      status: "disabled",
      disabled_at: ~U[2026-07-29 21:00:00Z]
    })
    |> Ash.update!(authorize?: false)
  end

  defp user_event(provider_updated_at, overrides \\ %{}) do
    data =
      Map.merge(
        %{
          provider_user_id: "directory_user_01",
          idp_id: "idp_user_01",
          email: "person@example.test",
          first_name: nil,
          last_name: nil,
          status: "active",
          provider_updated_at: provider_updated_at
        },
        overrides
      )

    event(:user, :upsert, "dsync.user.updated", provider_updated_at, data)
  end

  defp group_event(provider_updated_at) do
    event(:group, :upsert, "dsync.group.updated", provider_updated_at, %{
      provider_group_id: "directory_group_01",
      name: "Engineering",
      status: "active",
      provider_updated_at: provider_updated_at
    })
  end

  defp membership_event(provider_updated_at, status) do
    event(
      :membership,
      if(status == "active", do: :add, else: :remove),
      if(status == "active",
        do: "dsync.group.user_added",
        else: "dsync.group.user_removed"
      ),
      provider_updated_at,
      %{
        provider_group_id: "directory_group_01",
        provider_user_id: "directory_user_01",
        status: status,
        provider_updated_at: provider_updated_at
      }
    )
  end

  defp event(resource_kind, action, event_type, provider_occurred_at, data) do
    %DirectoryEvent{
      provider_event_id: unique("event"),
      event_type: event_type,
      directory_id: "ignored-after-boundary-selection",
      resource_kind: resource_kind,
      action: action,
      provider_occurred_at: provider_occurred_at,
      data: data
    }
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
