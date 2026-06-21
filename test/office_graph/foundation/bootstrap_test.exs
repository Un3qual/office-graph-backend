defmodule OfficeGraph.Foundation.BootstrapTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Authorization
  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.SessionContext

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
    end
  end
end
