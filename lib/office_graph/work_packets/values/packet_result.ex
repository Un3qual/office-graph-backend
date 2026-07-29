defmodule OfficeGraph.WorkPackets.PacketResult do
  @moduledoc """
  Typed result for an atomically assembled packet, version, and child rows.
  """

  use Ash.TypedStruct

  typed_struct do
    field :packet, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkPackets.WorkPacket]

    field :version, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkPackets.WorkPacketVersion]

    field :source_references, {:array, :struct},
      allow_nil?: false,
      constraints: [
        items: [instance_of: OfficeGraph.WorkPackets.WorkPacketSourceReference]
      ]

    field :required_checks, {:array, :struct},
      allow_nil?: false,
      constraints: [
        items: [instance_of: OfficeGraph.WorkPackets.WorkPacketRequiredCheck]
      ]
  end

  def build!(packet, version, source_references, required_checks) do
    new!(
      packet: packet,
      version: version,
      source_references: source_references,
      required_checks: required_checks
    )
  end
end

defmodule OfficeGraph.WorkPackets.PacketActionResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :reason, :term

    field :result, :struct, constraints: [instance_of: OfficeGraph.WorkPackets.PacketResult]
  end

  def accepted(result), do: new(status: "accepted", result: result)
  def rejected(reason), do: new(status: "rejected", reason: reason)

  def to_public_result(%__MODULE__{status: "accepted", result: result}),
    do: {:ok, result}

  def to_public_result(%__MODULE__{status: "rejected", reason: reason}),
    do: {:error, reason}
end
