defmodule OfficeGraph.WorkPackets.CommandResults.PacketMutation do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :packet, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkPackets.WorkPacket]

    field :packet_version, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkPackets.WorkPacketVersion]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :work_packet_command_payload

  def from_result(command, operation, result) do
    new(
      command: command,
      operation_id: operation.id,
      affected_ids: [
        TypedId.new!(type: "work_packet", id: result.packet.id),
        TypedId.new!(type: "work_packet_version", id: result.version.id)
      ],
      packet: result.packet,
      packet_version: result.version
    )
  end
end

defimpl Jason.Encoder, for: OfficeGraph.WorkPackets.CommandResults.PacketMutation do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        packet: %{
          id: result.packet.id,
          current_version_id: result.packet.current_version_id,
          title: result.packet.title,
          state: result.packet.state
        },
        packet_version: %{
          id: result.packet_version.id,
          version_number: result.packet_version.version_number,
          lifecycle_state: result.packet_version.lifecycle_state
        }
      },
      options
    )
  end
end
