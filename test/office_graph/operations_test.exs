defmodule OfficeGraph.OperationsTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Operations}
  alias OfficeGraph.WorkPackets.WorkPacket

  test "command operations replay equivalent input and reject changed input" do
    assert {:ok, bootstrap} =
             Foundation.bootstrap_local_owner(
               organization_slug: "operation-command-test",
               workspace_slug: "operation-command-test",
               initiative_slug: "operation-command-test",
               owner_email: "operation-command-test@office-graph.local"
             )

    packet_id = Ecto.UUID.generate()
    source_id = Ecto.UUID.generate()

    input = %{
      packet_id: packet_id,
      source_graph_item_ids: [source_id]
    }

    assert {:ok, first} =
             Operations.start_command(
               bootstrap.session,
               :work_packet_version_create,
               "version-1",
               input
             )

    assert {:ok, replay} =
             Operations.start_command(
               bootstrap.session,
               :work_packet_version_create,
               "version-1",
               input
             )

    assert replay.id == first.id
    assert replay.metadata["command_input_digest"] == first.metadata["command_input_digest"]

    changed_input = %{input | source_graph_item_ids: [Ecto.UUID.generate()]}

    assert {:error, {:command_idempotency_conflict, operation_id}} =
             Operations.start_command(
               bootstrap.session,
               :work_packet_version_create,
               "version-1",
               changed_input
             )

    assert operation_id == first.id
  end

  test "command digest preserves list order and normalizes map key order" do
    assert {:ok, bootstrap} =
             Foundation.bootstrap_local_owner(
               organization_slug: "operation-order-test",
               workspace_slug: "operation-order-test",
               initiative_slug: "operation-order-test",
               owner_email: "operation-order-test@office-graph.local"
             )

    first_id = Ecto.UUID.generate()
    second_id = Ecto.UUID.generate()

    assert {:ok, operation} =
             Operations.start_command(
               bootstrap.session,
               :work_packet_version_create,
               "version-order",
               %{packet_id: first_id, source_graph_item_ids: [first_id, second_id]}
             )

    assert :ok =
             Operations.validate_command_replay(operation, %{
               "source_graph_item_ids" => [first_id, second_id],
               "packet_id" => first_id
             })

    assert {:error, {:command_idempotency_conflict, operation_id}} =
             Operations.validate_command_replay(operation, %{
               packet_id: first_id,
               source_graph_item_ids: [second_id, first_id]
             })

    assert operation_id == operation.id
  end

  test "command target reads preserve the resource and requested id in not-found errors" do
    assert {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    missing_id = Ecto.UUID.generate()

    assert {:error, {:not_found, WorkPacket, ^missing_id}} =
             Operations.read_command_target(
               WorkPacket,
               :read_for_version_command,
               bootstrap.session,
               missing_id
             )
  end
end
