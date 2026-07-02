defmodule OfficeGraph.Foundation.BootstrapTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Identity, Operations, Repo}
  alias OfficeGraph.Identity.SessionContext

  require Ash.Query

  describe "bootstrap_local_owner/1" do
    test "creates the first organization owner context idempotently" do
      attrs = [
        organization_name: "Office Graph Test",
        organization_slug: "office-graph-test",
        workspace_name: "Engineering",
        workspace_slug: "engineering",
        initiative_name: "Walking Skeleton",
        initiative_slug: "walking-skeleton",
        owner_email: "owner@example.test",
        owner_name: "Local Owner"
      ]

      assert {:ok, first} = Foundation.bootstrap_local_owner(attrs)
      assert {:ok, second} = Foundation.bootstrap_local_owner(attrs)

      assert first.organization.id == second.organization.id
      assert first.workspace.id == second.workspace.id
      assert first.initiative.id == second.initiative.id
      assert first.principal.id == second.principal.id
      assert first.profile.id == second.profile.id
      assert first.role_assignment.id == second.role_assignment.id
      assert first.policy_bundle.id == second.policy_bundle.id
      assert first.session.principal_id == first.principal.id
      assert first.session.organization_id == first.organization.id
      assert MapSet.member?(first.session.capabilities, "skeleton.read")

      assert Ash.get!(OfficeGraph.Tenancy.Organization, first.organization.id, authorize?: false)
      assert Ash.get!(OfficeGraph.Tenancy.Workspace, first.workspace.id, authorize?: false)
      assert Ash.get!(OfficeGraph.Tenancy.Initiative, first.initiative.id, authorize?: false)
      assert Ash.get!(OfficeGraph.Identity.Principal, first.principal.id, authorize?: false)
      assert Ash.get!(OfficeGraph.Identity.PrincipalProfile, first.profile.id, authorize?: false)

      assert Ash.get!(OfficeGraph.Authorization.RoleAssignment, first.role_assignment.id,
               authorize?: false
             )

      assert Ash.get!(OfficeGraph.Authorization.PolicyBundle, first.policy_bundle.id,
               authorize?: false
             )
    end

    test "creates separate owner assignments for the same owner across workspaces" do
      owner_attrs = [
        owner_email: "same-owner@example.test",
        owner_name: "Same Owner"
      ]

      assert {:ok, first} =
               Foundation.bootstrap_local_owner(
                 owner_attrs ++
                   [
                     workspace_name: "Workspace One",
                     workspace_slug: "workspace-one",
                     initiative_name: "Initiative One",
                     initiative_slug: "initiative-one"
                   ]
               )

      assert {:ok, second} =
               Foundation.bootstrap_local_owner(
                 owner_attrs ++
                   [
                     workspace_name: "Workspace Two",
                     workspace_slug: "workspace-two",
                     initiative_name: "Initiative Two",
                     initiative_slug: "initiative-two"
                   ]
               )

      assert first.organization.id == second.organization.id
      assert first.principal.id == second.principal.id
      assert first.role_assignment.id != second.role_assignment.id
      assert first.role_assignment.workspace_id == first.workspace.id
      assert second.role_assignment.workspace_id == second.workspace.id

      assignment_count =
        OfficeGraph.Authorization.RoleAssignment
        |> Ash.Query.filter(
          principal_id == ^first.principal.id and organization_id == ^first.organization.id
        )
        |> Ash.count!(authorize?: false)

      assert assignment_count == 2
    end

    test "rerun after revoking local owner session returns a usable replacement session" do
      attrs = unique_bootstrap_attrs("revoked-local-owner")

      assert {:ok, first} = Foundation.bootstrap_local_owner(attrs)
      revoke_session!(first.session.session_id)

      assert {:ok, second} = Foundation.bootstrap_local_owner(attrs)

      assert second.session.session_id != first.session.session_id
      assert {:error, :forbidden} = Identity.validate_session_context(first.session)
      assert :ok = Identity.validate_session_context(second.session)
      assert {:ok, _operation} = Operations.start_operation(second.session, :manual_intake_submit)
    end
  end

  describe "authorize/3" do
    test "allows owner skeleton actions and denies a principal without capabilities" do
      assert {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

      for action <- [
            :skeleton_read,
            :manual_intake_submit,
            :proposed_change_apply,
            :evidence_link,
            :verification_complete
          ] do
        assert :ok =
                 Authorization.authorize(bootstrap.session, action,
                   organization_id: bootstrap.organization.id
                 )
      end

      unauthorized = %SessionContext{
        principal_id: Ecto.UUID.generate(),
        session_id: Ecto.UUID.generate(),
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        capabilities: MapSet.new()
      }

      for action <- [
            :skeleton_read,
            :manual_intake_submit,
            :proposed_change_apply,
            :evidence_link,
            :verification_complete
          ] do
        assert {:error, :forbidden} =
                 Authorization.authorize(unauthorized, action,
                   organization_id: bootstrap.organization.id
                 )
      end

      assert {:error, :forbidden} =
               Authorization.authorize(bootstrap.session, :unknown_action,
                 organization_id: bootstrap.organization.id
               )
    end

    test "rejects forged capability hints without role grants" do
      assert {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

      bare_principal =
        Ash.create!(
          OfficeGraph.Identity.Principal,
          %{
            id: Ecto.UUID.generate(),
            email: "bare-policy-#{System.unique_integer([:positive])}@office-graph.local",
            kind: "human",
            status: "active"
          },
          action: :create,
          authorize?: false
        )

      bare_session =
        Ash.create!(
          OfficeGraph.Identity.Session,
          %{
            id: Ecto.UUID.generate(),
            principal_id: bare_principal.id,
            organization_id: bootstrap.organization.id,
            workspace_id: bootstrap.workspace.id,
            purpose: "forged_capability_test"
          },
          action: :create,
          authorize?: false
        )

      forged = %SessionContext{
        principal_id: bare_principal.id,
        session_id: bare_session.id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        capabilities: MapSet.new(["manual_intake.submit"])
      }

      assert {:error, :forbidden} =
               Authorization.authorize(forged, :manual_intake_submit,
                 organization_id: bootstrap.organization.id
               )
    end

    test "revalidates trusted session capabilities against live role assignments" do
      assert {:ok, bootstrap} =
               Foundation.bootstrap_local_owner(unique_bootstrap_attrs("trusted-revalidation"))

      assert :ok =
               Authorization.authorize(bootstrap.session, :manual_intake_submit,
                 organization_id: bootstrap.organization.id
               )

      delete_role_assignment!(bootstrap.role_assignment.id)

      assert {:error, :forbidden} =
               Authorization.authorize(bootstrap.session, :manual_intake_submit,
                 organization_id: bootstrap.organization.id
               )
    end

    test "rejects role assignments whose role belongs to another organization" do
      assert {:ok, bootstrap} =
               Foundation.bootstrap_local_owner(unique_bootstrap_attrs("local-role"))

      assert {:ok, foreign} =
               Foundation.bootstrap_local_owner(unique_bootstrap_attrs("foreign-role"))

      bare_principal =
        Ash.create!(
          OfficeGraph.Identity.Principal,
          %{
            id: Ecto.UUID.generate(),
            email: "cross-role-#{System.unique_integer([:positive])}@office-graph.local",
            kind: "human",
            status: "active"
          },
          action: :create,
          authorize?: false
        )

      bare_session =
        Ash.create!(
          OfficeGraph.Identity.Session,
          %{
            id: Ecto.UUID.generate(),
            principal_id: bare_principal.id,
            organization_id: bootstrap.organization.id,
            workspace_id: bootstrap.workspace.id,
            purpose: "cross_org_role_test"
          },
          action: :create,
          authorize?: false
        )

      Ash.create!(
        OfficeGraph.Authorization.RoleAssignment,
        %{
          id: Ecto.UUID.generate(),
          principal_id: bare_principal.id,
          role_id: foreign.role_assignment.role_id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id
        },
        action: :create,
        authorize?: false
      )

      cross_org_context = %SessionContext{
        principal_id: bare_principal.id,
        session_id: bare_session.id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        capabilities: MapSet.new(["manual_intake.submit"])
      }

      assert {:error, :forbidden} =
               Authorization.authorize(cross_org_context, :manual_intake_submit,
                 organization_id: bootstrap.organization.id
               )
    end

    test "rejects sessions whose principal is inactive" do
      assert {:ok, bootstrap} =
               Foundation.bootstrap_local_owner(unique_bootstrap_attrs("inactive-principal"))

      deactivate_principal!(bootstrap.principal.id)

      assert {:error, :forbidden} = Identity.validate_session_context(bootstrap.session)

      assert {:error, :forbidden} =
               Operations.start_operation(bootstrap.session, :manual_intake_submit)

      assert {:error, :forbidden} =
               Authorization.authorize(bootstrap.session, :manual_intake_submit,
                 organization_id: bootstrap.organization.id
               )
    end
  end

  defp unique_bootstrap_attrs(label) do
    suffix = "#{label}-#{System.unique_integer([:positive])}"

    [
      organization_name: "Office Graph #{suffix}",
      organization_slug: suffix,
      workspace_name: "Workspace #{suffix}",
      workspace_slug: suffix,
      initiative_name: "Initiative #{suffix}",
      initiative_slug: suffix,
      owner_email: "#{suffix}@example.test",
      owner_name: "Owner #{suffix}"
    ]
  end

  defp revoke_session!(session_id) do
    now = DateTime.utc_now()

    Repo.query!(
      "UPDATE sessions SET revoked_at = $1, updated_at = $1 WHERE id = $2",
      [now, db_uuid(session_id)]
    )
  end

  defp deactivate_principal!(principal_id) do
    now = DateTime.utc_now()

    Repo.query!(
      "UPDATE principals SET status = 'inactive', updated_at = $1 WHERE id = $2",
      [now, db_uuid(principal_id)]
    )
  end

  defp delete_role_assignment!(role_assignment_id) do
    Repo.query!("DELETE FROM role_assignments WHERE id = $1", [db_uuid(role_assignment_id)])
  end

  defp db_uuid(uuid), do: Ecto.UUID.dump!(uuid)
end
