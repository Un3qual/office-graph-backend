defmodule OfficeGraph.WorkPackets.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.WorkPackets.WorkPacket, :get_work_packet, :read
      list OfficeGraph.WorkPackets.WorkPacket, :list_work_packets, :read, relay?: true
    end
  end

  json_api do
    routes do
      base_route "/work-packets", OfficeGraph.WorkPackets.WorkPacket do
        get(:read, primary?: true)
        index :read
      end
    end
  end

  resources do
    resource OfficeGraph.WorkPackets.WorkPacket
    resource OfficeGraph.WorkPackets.WorkPacketVersion
    resource OfficeGraph.WorkPackets.WorkPacketSourceReference
    resource OfficeGraph.WorkPackets.WorkPacketRequiredCheck
  end
end
