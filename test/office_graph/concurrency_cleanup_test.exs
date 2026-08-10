defmodule OfficeGraph.ConcurrencyCleanupTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Operations, WorkPackets}
  alias OfficeGraph.Identity.Principal
  alias OfficeGraph.Tenancy.Organization
  alias OfficeGraph.TestSupport.ConcurrencyCleanup
  alias OfficeGraph.WorkPackets.{WorkPacket, WorkPacketVersion}

  test "cleans a bootstrapped scope through the canonical resource contracts" do
    suffix = System.unique_integer([:positive])
    organization_slug = "cleanup-#{suffix}"
    owner_email = "cleanup-#{suffix}@example.test"

    assert {:ok, bootstrap} =
             Foundation.bootstrap_local_owner(
               organization_name: "Cleanup #{suffix}",
               organization_slug: organization_slug,
               workspace_slug: "workspace-#{suffix}",
               initiative_slug: "initiative-#{suffix}",
               owner_email: owner_email
             )

    assert Ash.get!(Organization, bootstrap.organization.id, authorize?: false)
    assert Ash.get!(Principal, bootstrap.principal.id, authorize?: false)

    ConcurrencyCleanup.cleanup_tenancy_scope!(organization_slug)
    ConcurrencyCleanup.cleanup_owner_principal!(owner_email)

    assert {:ok, nil} =
             Ash.get(Organization, bootstrap.organization.id,
               authorize?: false,
               not_found_error?: false
             )

    assert {:ok, nil} =
             Ash.get(Principal, bootstrap.principal.id,
               authorize?: false,
               not_found_error?: false
             )
  end

  test "clears a packet's current version before deleting the packet scope" do
    suffix = System.unique_integer([:positive])

    assert {:ok, bootstrap} =
             Foundation.bootstrap_local_owner(
               organization_name: "Packet Cleanup #{suffix}",
               organization_slug: "packet-cleanup-#{suffix}",
               workspace_slug: "packet-workspace-#{suffix}",
               initiative_slug: "packet-initiative-#{suffix}",
               owner_email: "packet-cleanup-#{suffix}@example.test"
             )

    assert {:ok, operation} =
             Operations.start_operation(bootstrap.session, :work_packet_create,
               idempotency_key: "packet-cleanup-#{suffix}"
             )

    assert {:ok, packet_result} =
             WorkPackets.create_packet(bootstrap.session, operation, %{
               title: "Cleanup packet",
               objective: "Exercise canonical packet cleanup.",
               context_summary: "A packet and version form a deliberate current-version cycle.",
               requirements: "Clear the current version before deleting either side.",
               success_criteria: "Both canonical records are removed.",
               autonomy_posture: "human_supervised",
               source_graph_item_ids: [],
               verification_check_ids: []
             })

    assert packet_result.packet.current_version_id == packet_result.version.id

    ConcurrencyCleanup.cleanup_work_run_verification_scope_by_id!(bootstrap.organization.id)

    assert {:ok, nil} =
             Ash.get(WorkPacket, packet_result.packet.id,
               authorize?: false,
               not_found_error?: false
             )

    assert {:ok, nil} =
             Ash.get(WorkPacketVersion, packet_result.version.id,
               authorize?: false,
               not_found_error?: false
             )
  end
end
