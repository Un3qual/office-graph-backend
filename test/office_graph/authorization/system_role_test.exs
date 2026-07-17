defmodule OfficeGraph.Authorization.SystemRoleTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Authorization, Foundation, Identity}

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
end
