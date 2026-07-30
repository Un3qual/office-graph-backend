defmodule OfficeGraph.Authorization.LocalDevelopmentRolesTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Identity}

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
