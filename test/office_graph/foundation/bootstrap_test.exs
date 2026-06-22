defmodule OfficeGraph.Foundation.BootstrapTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Authorization
  alias OfficeGraph.Foundation
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
  end
end
