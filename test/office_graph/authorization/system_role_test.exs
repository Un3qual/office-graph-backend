defmodule OfficeGraph.Authorization.SystemRoleTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Identity, Repo}

  test "system capabilities stay attached to the exact assignment scope" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:ok, principal} =
             Identity.ensure_system_principal(
               "scoped-system-role@office-graph.local",
               "service"
             )

    assert :ok =
             Authorization.ensure_system_role(
               principal,
               %{organization_id: bootstrap.organization.id, workspace_id: nil},
               [:provider_webhook_receive]
             )

    assert :ok =
             Authorization.ensure_system_role(
               principal,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id
               },
               [:integration_reconcile]
             )

    assert :ok =
             Authorization.authorize_system_principal(
               principal.id,
               bootstrap.organization.id,
               bootstrap.workspace.id,
               :integration_reconcile
             )

    assert {:error, :forbidden} =
             Authorization.authorize_system_principal(
               principal.id,
               bootstrap.organization.id,
               nil,
               :integration_reconcile
             )
  end

  test "system role setup preserves classified principal lookup failures" do
    assert {:error, :integration_storage_unavailable} =
             Authorization.ensure_system_role(
               %{id: "invalid-principal-id"},
               %{organization_id: Ecto.UUID.generate(), workspace_id: nil},
               [:provider_webhook_receive]
             )
  end

  test "system role setup preserves role persistence failures" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:ok, principal} =
             Identity.ensure_system_principal(
               "unavailable-system-role@office-graph.local",
               "service"
             )

    Repo.query!("""
    ALTER TABLE roles
    ADD CONSTRAINT test_system_role_write_storage
    CHECK (key NOT LIKE 'system:%')
    """)

    result =
      try do
        Authorization.ensure_system_role(
          principal,
          %{organization_id: bootstrap.organization.id, workspace_id: bootstrap.workspace.id},
          [:integration_reconcile]
        )
      after
        Repo.query!("""
        ALTER TABLE roles
        DROP CONSTRAINT test_system_role_write_storage
        """)
      end

    assert {:error, :integration_storage_unavailable} = result
  end
end
