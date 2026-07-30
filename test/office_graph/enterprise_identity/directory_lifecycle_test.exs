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

  alias OfficeGraph.Authorization.{Role, RoleAssignment}
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

  test "membership removal applies after its user and group were deleted" do
    context = enterprise_context("membership-removal-after-dependencies")
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

    assert {:ok, %{resource: %DirectoryMembership{} = membership}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               membership_event(initial_time, "active"),
               context.operation.id
             )

    deleted_time = DateTime.add(initial_time, 60, :second)

    assert {:ok, %{resource: %DirectoryUser{status: "deleted"}}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(deleted_time, %{status: "deleted"}),
               context.operation.id
             )

    assert {:ok, %{resource: %DirectoryGroup{status: "deleted"}}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               group_event(deleted_time, %{status: "deleted"}),
               context.operation.id
             )

    removed_time = DateTime.add(initial_time, 120, :second)

    assert {:ok, %{status: :applied, resource: removed}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               membership_event(removed_time, "removed"),
               context.operation.id
             )

    assert removed.id == membership.id
    assert removed.directory_user_id == user.id
    assert removed.directory_group_id == group.id
    assert removed.status == "removed"
    assert DateTime.compare(removed.removed_at, removed_time) == :eq
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

  test "directory deprovisioning preserves SSO while another directory basis remains active" do
    context = enterprise_context("multi-directory-deprovision")
    active_time = ~U[2026-07-29 20:00:00Z]

    assert {:ok, %{resource: %DirectoryUser{} = first_user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(active_time),
               context.operation.id
             )

    second_directory =
      Ash.create!(
        Directory,
        %{
          connection_id: context.connection.id,
          operation_id: context.operation.id,
          provider_directory_id: unique("second-workos-directory"),
          status: "active",
          provider_updated_at: ~U[2026-07-29 19:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    assert {:ok, %{resource: %DirectoryUser{} = second_user}} =
             EnterpriseIdentity.apply_directory_event(
               second_directory.id,
               user_event(active_time, %{provider_user_id: "directory_user_02"}),
               context.operation.id
             )

    assert second_user.principal_id == first_user.principal_id
    assert second_user.external_identity_link_id != first_user.external_identity_link_id

    sso_link =
      Ash.create!(
        ExternalIdentityLink,
        %{
          principal_id: first_user.principal_id,
          provider: "workos_sso",
          provider_tenant: context.connection.provider_organization_id,
          subject: "connection_01:idp_user_01",
          verified_email: first_user.email,
          status: "active",
          linking_state: "linked",
          first_linked_at: active_time
        },
        action: :create,
        authorize?: false
      )

    assert {:ok, %{status: :applied}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(DateTime.add(active_time, 60, :second), %{status: "deleted"}),
               context.operation.id
             )

    assert Ash.get!(ExternalIdentityLink, sso_link.id, authorize?: false).status == "active"
    assert Ash.get!(Principal, first_user.principal_id, authorize?: false).status == "active"

    assert {:ok, linked} =
             Identity.reconcile_workos_sso_identity(
               %{
                 subject: sso_link.subject,
                 verified_email: first_user.email
               },
               context.connection.provider_organization_id
             )

    assert linked.principal.id == first_user.principal_id
  end

  test "an IdP subject change enters review and disables the authentication basis" do
    context = enterprise_context("idp-subject-change")
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

    assert {:ok, %{status: :review_required, resource: reviewed_user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(DateTime.add(active_time, 60, :second), %{idp_id: "idp_user_02"}),
               context.operation.id
             )

    assert reviewed_user.review_reason == "provider_subject_conflict"

    assert Ash.get!(
             ExternalIdentityLink,
             user.external_identity_link_id,
             authorize?: false
           ).status == "disabled"

    assert Ash.get!(ExternalIdentityLink, sso_link.id, authorize?: false).status == "disabled"
  end

  test "a disabled identity basis cannot authorize a new WorkOS SSO subject" do
    context = enterprise_context("disabled-basis-new-sso-subject")
    active_time = ~U[2026-07-29 20:00:00Z]

    assert {:ok, %{resource: %DirectoryUser{} = user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(active_time),
               context.operation.id
             )

    Ash.create!(
      ExternalIdentityLink,
      %{
        principal_id: user.principal_id,
        provider: "oidc",
        provider_tenant: "https://identity.example.test",
        subject: unique("durable-subject"),
        verified_email: user.email,
        status: "active",
        linking_state: "linked",
        first_linked_at: active_time
      },
      action: :create,
      authorize?: false
    )

    assert {:ok, %{resource: %DirectoryUser{status: "deleted"}}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(DateTime.add(active_time, 60, :second), %{status: "deleted"}),
               context.operation.id
             )

    assert {:review, "verified_identifier_conflict"} =
             Identity.reconcile_workos_sso_identity(
               %{
                 subject: "connection_01:idp_user_rebound",
                 verified_email: user.email
               },
               context.connection.provider_organization_id
             )

    refute ExternalIdentityLink
           |> Ash.Query.filter(
             provider == "workos_sso" and
               provider_tenant == ^context.connection.provider_organization_id and
               subject == "connection_01:idp_user_rebound" and status == "active"
           )
           |> Ash.exists?(authorize?: false)
  end

  test "principal email variants reuse one canonical indexed identity" do
    context = enterprise_context("canonical-email")
    email = "canonical@example.test"

    principal =
      Ash.create!(
        Principal,
        %{email: String.upcase(email), kind: "human", status: "active"},
        action: :ensure,
        authorize?: false
      )

    replayed_principal =
      Ash.create!(
        Principal,
        %{email: " #{email} ", kind: "human", status: "active"},
        action: :ensure,
        authorize?: false
      )

    assert replayed_principal.id == principal.id
    assert replayed_principal.email == email

    assert {:ok, %{status: :applied, resource: user}} =
             EnterpriseIdentity.apply_directory_event(
               context.directory.id,
               user_event(~U[2026-07-29 20:00:00Z], %{email: email}),
               context.operation.id
             )

    assert user.status == "active"
    assert user.principal_id == principal.id
    assert is_binary(user.external_identity_link_id)
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

    provider_directory_id = unique("managed-directory")

    assert {:ok, directory} =
             EnterpriseIdentity.bind_directory(bootstrap.session, operation, %{
               connection_id: connection.id,
               provider_directory_id: provider_directory_id,
               status: "active",
               provider_updated_at: ~U[2026-07-29 19:00:00Z]
             })

    assert directory.connection_id == connection.id
    assert directory.operation_id == operation.id

    assert {:ok, replayed_directory} =
             EnterpriseIdentity.bind_directory(bootstrap.session, operation, %{
               connection_id: connection.id,
               provider_directory_id: provider_directory_id,
               status: "active",
               provider_updated_at: ~U[2026-07-29 19:00:00Z]
             })

    assert replayed_directory.id == directory.id

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
             EnterpriseIdentity.bind_directory(forged_session, operation, %{
               connection_id: connection.id,
               provider_directory_id: unique("forged-directory"),
               status: "active",
               provider_updated_at: ~U[2026-07-29 19:00:00Z]
             })

    assert {:error, :forbidden} =
             EnterpriseIdentity.set_connection_lifecycle(
               forged_session,
               operation,
               connection.id,
               %{status: "disabled"}
             )
  end

  test "organization-wide connection and mapping management preserve explicit nil scope" do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_slug: unique("organization-management-organization"),
        workspace_slug: unique("organization-management-workspace"),
        initiative_slug: unique("organization-management-initiative"),
        owner_email: "#{unique("organization-management-owner")}@example.test"
      )

    {:ok, webhook_principal} =
      Identity.ensure_system_principal(
        "#{unique("organization-management-webhook")}@office-graph.local",
        "webhook"
      )

    {:ok, workspace_operation} =
      Operations.start_operation(bootstrap.session, :enterprise_identity_manage)

    assert {:error, :forbidden} =
             EnterpriseIdentity.create_connection(
               bootstrap.session,
               workspace_operation,
               %{
                 workspace_id: nil,
                 webhook_principal_id: webhook_principal.id,
                 provider: "workos",
                 provider_organization_id: unique("denied-workos-organization"),
                 directory_requirement: "required",
                 status: "active"
               }
             )

    role =
      Role
      |> Ash.Query.filter(organization_id == ^bootstrap.organization.id and key == "owner")
      |> Ash.read_one!(authorize?: false)

    Ash.create!(
      RoleAssignment,
      %{
        principal_id: bootstrap.principal.id,
        role_id: role.id,
        organization_id: bootstrap.organization.id,
        workspace_id: nil
      },
      action: :create,
      authorize?: false
    )

    assert :ok =
             Authorization.ensure_system_role(
               webhook_principal,
               %{organization_id: bootstrap.organization.id, workspace_id: nil},
               [:provider_webhook_receive]
             )

    {:ok, operation} =
      Operations.start_operation(bootstrap.session, :enterprise_identity_manage)

    assert {:ok, workspace_connection} =
             EnterpriseIdentity.create_connection(bootstrap.session, operation, %{
               webhook_principal_id: webhook_principal.id,
               provider: "workos",
               provider_organization_id: unique("workspace-workos-organization"),
               directory_requirement: "required",
               status: "active"
             })

    workspace_directory =
      Ash.create!(
        Directory,
        %{
          connection_id: workspace_connection.id,
          operation_id: operation.id,
          provider_directory_id: unique("workspace-managed-directory"),
          status: "active",
          provider_updated_at: ~U[2026-07-30 19:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    workspace_group =
      Ash.create!(
        DirectoryGroup,
        %{
          directory_id: workspace_directory.id,
          provider_group_id: unique("workspace-managed-group"),
          name: "Workspace Engineering",
          status: "active",
          provider_updated_at: ~U[2026-07-30 20:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    assert {:error, :forbidden} =
             EnterpriseIdentity.create_group_role_mapping(
               bootstrap.session,
               operation,
               %{
                 workspace_id: nil,
                 directory_group_id: workspace_group.id,
                 role_id: role.id,
                 status: "active"
               }
             )

    assert {:ok, connection} =
             EnterpriseIdentity.create_connection(bootstrap.session, operation, %{
               workspace_id: nil,
               webhook_principal_id: webhook_principal.id,
               provider: "workos",
               provider_organization_id: unique("organization-workos-organization"),
               directory_requirement: "required",
               status: "active"
             })

    assert connection.workspace_id == nil

    directory =
      Ash.create!(
        Directory,
        %{
          connection_id: connection.id,
          operation_id: operation.id,
          provider_directory_id: unique("organization-managed-directory"),
          status: "active",
          provider_updated_at: ~U[2026-07-30 19:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    group =
      Ash.create!(
        DirectoryGroup,
        %{
          directory_id: directory.id,
          provider_group_id: unique("organization-managed-group"),
          name: "Organization Engineering",
          status: "active",
          provider_updated_at: ~U[2026-07-30 20:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    assert {:ok, mapping} =
             EnterpriseIdentity.create_group_role_mapping(
               bootstrap.session,
               operation,
               %{
                 workspace_id: nil,
                 directory_group_id: group.id,
                 role_id: role.id,
                 status: "active"
               }
             )

    assert mapping.workspace_id == nil

    assert {:ok, disabled_mapping} =
             EnterpriseIdentity.set_group_role_mapping_lifecycle(
               bootstrap.session,
               operation,
               mapping.id,
               %{
                 workspace_id: nil,
                 status: "disabled",
                 disabled_at: DateTime.utc_now()
               }
             )

    assert disabled_mapping.workspace_id == nil
    assert disabled_mapping.status == "disabled"
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

  defp group_event(provider_updated_at, overrides \\ %{}) do
    data =
      Map.merge(
        %{
          provider_group_id: "directory_group_01",
          name: "Engineering",
          status: "active",
          provider_updated_at: provider_updated_at
        },
        overrides
      )

    event(:group, :upsert, "dsync.group.updated", provider_updated_at, data)
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
