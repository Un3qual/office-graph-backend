defmodule OfficeGraph.WorkPackets.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.WorkPackets.WorkPacket, :get_work_packet, :read
      list OfficeGraph.WorkPackets.WorkPacket, :list_work_packets, :read, relay?: true

      get OfficeGraph.WorkPackets.WorkPacketVersion, :get_work_packet_version, :read

      list OfficeGraph.WorkPackets.WorkPacketVersion, :list_work_packet_versions, :read,
        relay?: true

      get OfficeGraph.WorkPackets.WorkPacketSourceReference,
          :get_work_packet_source_reference,
          :read

      list OfficeGraph.WorkPackets.WorkPacketSourceReference,
           :list_work_packet_source_references,
           :read,
           relay?: true

      get OfficeGraph.WorkPackets.WorkPacketRequiredCheck,
          :get_work_packet_required_check,
          :read

      list OfficeGraph.WorkPackets.WorkPacketRequiredCheck,
           :list_work_packet_required_checks,
           :read,
           relay?: true
    end

    mutations do
      action OfficeGraph.WorkPackets.WorkPacket,
             :create_work_packet,
             :create_work_packet do
        relay_id_translations(
          input: [
            source_graph_item_ids: :graph_item,
            verification_check_ids: :verification_check
          ]
        )
      end

      action OfficeGraph.WorkPackets.WorkPacket,
             :create_work_packet_version,
             :create_work_packet_version do
        relay_id_translations(
          input: [
            packet_id: :work_packet,
            expected_current_version_id: :work_packet_version,
            source_graph_item_ids: :graph_item,
            verification_check_ids: :verification_check
          ]
        )
      end
    end
  end

  json_api do
    routes do
      base_route "/work-packets", OfficeGraph.WorkPackets.WorkPacket do
        get(:read, primary?: true)
        index :read
      end

      base_route "/work-packet-versions", OfficeGraph.WorkPackets.WorkPacketVersion do
        get(:read, primary?: true)
        index :read
      end

      base_route "/work-packet-source-references",
                 OfficeGraph.WorkPackets.WorkPacketSourceReference do
        get(:read, primary?: true)
        index :read
      end

      base_route "/work-packet-required-checks",
                 OfficeGraph.WorkPackets.WorkPacketRequiredCheck do
        get(:read, primary?: true)
        index :read
      end

      route(
        OfficeGraph.WorkPackets.WorkPacket,
        :post,
        "/commands/create-work-packet",
        :create_work_packet
      )

      route(
        OfficeGraph.WorkPackets.WorkPacket,
        :post,
        "/commands/create-work-packet-version",
        :create_work_packet_version
      )
    end
  end

  resources do
    resource OfficeGraph.WorkPackets.WorkPacket
    resource OfficeGraph.WorkPackets.WorkPacketVersion
    resource OfficeGraph.WorkPackets.WorkPacketSourceReference
    resource OfficeGraph.WorkPackets.WorkPacketRequiredCheck
  end
end
