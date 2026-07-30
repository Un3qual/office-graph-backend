defmodule OfficeGraph.Identity.LocalDevelopmentIdentityTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Authentication.LocalDevelopmentFixtures
  alias OfficeGraph.Authorization.ReferenceCatalog
  alias OfficeGraph.Identity

  test "local development fixtures expose only stable server-owned keys" do
    fixtures = LocalDevelopmentFixtures.all()

    assert Enum.map(fixtures, & &1.key) ==
             ~w(owner workspace_admin member deprovisioned_member)

    assert Enum.uniq_by(fixtures, & &1.subject) == fixtures
    assert Enum.uniq_by(fixtures, & &1.email) == fixtures
    assert LocalDevelopmentFixtures.fetch("unknown") == :error

    assert Enum.all?(fixtures, fn fixture ->
             fixture.provider == "local_development" and
               fixture.provider_tenant == "office_graph_development" and
               is_atom(fixture.role_profile)
           end)

    {:ok, admin} = LocalDevelopmentFixtures.fetch("workspace_admin")
    {:ok, member} = LocalDevelopmentFixtures.fetch("member")

    assert :proposed_change_apply in admin.actions
    refute :enterprise_identity_manage in admin.actions

    assert member.actions ==
             ~w(skeleton_read durable_delivery_read manual_intake_submit conversation_write)a

    assert Enum.all?(admin.actions ++ member.actions, &is_atom/1)
    assert {:ok, _keys} = ReferenceCatalog.capability_keys(admin.actions)
    assert {:error, :unknown_capability_action} = ReferenceCatalog.capability_keys([:unknown])
  end

  test "identity setup is idempotent and does not reactivate disabled facts" do
    fixture = fixture!("member")

    assert {:ok, first} = Identity.ensure_local_development_identity(fixture)

    first.principal
    |> Ash.Changeset.for_update(:set_status, %{status: "disabled"})
    |> Ash.update!(authorize?: false)

    now = DateTime.utc_now()

    first.external_identity_link
    |> Ash.Changeset.for_update(:set_lifecycle, %{
      status: "disabled",
      linking_state: "linked",
      review_reason: "manually_disabled",
      disabled_at: now
    })
    |> Ash.update!(authorize?: false)

    assert {:ok, replayed} = Identity.ensure_local_development_identity(fixture)
    assert replayed.principal.id == first.principal.id
    assert replayed.principal.status == "disabled"
    assert replayed.profile.id == first.profile.id
    assert replayed.external_identity_link.id == first.external_identity_link.id
    assert replayed.external_identity_link.status == "disabled"
  end

  test "exact lookup returns retained disabled facts and rejects drift" do
    fixture = fixture!("deprovisioned_member")

    assert {:ok, seeded} = Identity.ensure_local_development_identity(fixture)
    assert {:ok, resolved} = Identity.local_development_identity(fixture)
    assert resolved.principal.id == seeded.principal.id
    assert resolved.principal.status == "disabled"
    assert resolved.external_identity_link.status == "disabled"

    drifted = %{fixture | email: "attacker@example.test"}

    assert {:error, :local_development_fixture_missing} =
             Identity.local_development_identity(drifted)
  end

  defp fixture!(key) do
    {:ok, fixture} = LocalDevelopmentFixtures.fetch(key)
    fixture
  end
end
