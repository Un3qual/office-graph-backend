defmodule OfficeGraph.Authorization.LocalDevelopmentRolesTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Identity}
  alias OfficeGraph.Authorization.{Capability, RoleCapability}

  require Ash.Query

  test "seeded fixtures exercise distinct ordinary authorization profiles" do
    assert {:ok, seeded} =
             Foundation.seed_local_development_fixtures(
               organization_name: "Local Role Test",
               organization_slug: "local-role-test",
               workspace_name: "Development",
               workspace_slug: "development",
               initiative_name: "Local Authentication",
               initiative_slug: "local-authentication"
             )

    assert {:ok, owner} = issue_session(seeded, "owner")
    assert {:ok, admin} = issue_session(seeded, "workspace_admin")
    assert {:ok, member} = issue_session(seeded, "member")

    assert :ok = authorize(owner, seeded, :proposed_change_apply)
    assert :ok = authorize(admin, seeded, :proposed_change_apply)
    assert {:error, :forbidden} = authorize(member, seeded, :proposed_change_apply)

    assert :ok = authorize(member, seeded, :manual_intake_submit)
    assert {:error, :forbidden} = authorize(admin, seeded, :enterprise_identity_manage)

    assert {:error, :invalid_identity} =
             issue_session(seeded, "deprovisioned_member")
  end

  test "seed replay removes capability memberships outside the local role manifest" do
    attrs = [
      organization_name: "Local Role Repair Test",
      organization_slug: "local-role-repair-test",
      workspace_name: "Development",
      workspace_slug: "development",
      initiative_name: "Local Authentication",
      initiative_slug: "local-authentication"
    ]

    assert {:ok, seeded} = Foundation.seed_local_development_fixtures(attrs)

    member_role_id = seeded.fixtures["member"].role_assignment.role_id

    extra_capability =
      Ash.get!(Capability, %{key: "proposed_change.apply"}, authorize?: false)

    Ash.create!(
      RoleCapability,
      %{role_id: member_role_id, capability_id: extra_capability.id},
      action: :ensure,
      authorize?: false
    )

    assert {:ok, repaired} = Foundation.seed_local_development_fixtures(attrs)

    assert [] =
             RoleCapability
             |> Ash.Query.filter(
               role_id == ^member_role_id and capability_id == ^extra_capability.id
             )
             |> Ash.read!(authorize?: false)

    assert {:ok, member} = issue_session(repaired, "member")
    assert {:error, :forbidden} = authorize(member, repaired, :proposed_change_apply)
  end

  defp issue_session(seeded, key) do
    fixture = seeded.fixtures[key]

    case Identity.issue_human_session(
           fixture.identity.principal,
           fixture.identity.external_identity_link,
           %{
             organization_id: seeded.bootstrap.organization.id,
             workspace_id: seeded.bootstrap.workspace.id
           },
           authentication_method: "local_development",
           source_surface: "test",
           trace_id: "local-role-#{key}",
           ttl_seconds: 3_600
         ) do
      {:ok, %{session_context: session_context}} -> {:ok, session_context}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize(session, seeded, action) do
    Authorization.authorize(session, action, organization_id: seeded.bootstrap.organization.id)
  end
end
