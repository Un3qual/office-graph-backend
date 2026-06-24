defmodule OfficeGraph.WorkPackets.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.WorkPackets.WorkPacket
    resource OfficeGraph.WorkPackets.WorkPacketVersion
    resource OfficeGraph.WorkPackets.WorkPacketSourceReference
    resource OfficeGraph.WorkPackets.WorkPacketRequiredCheck
  end
end
