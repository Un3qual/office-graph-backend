import { readInlineData, useLazyLoadQuery } from "react-relay";
import type {
  PacketsRoutePacketFragment$data,
  PacketsRoutePacketFragment$key
} from "../../relay/__generated__/PacketsRoutePacketFragment.graphql";
import type { PacketsRouteQuery as PacketsRouteOperation } from "../../relay/__generated__/PacketsRouteQuery.graphql";
import type { PacketsWorkspaceDetailQuery as PacketsWorkspaceDetailOperation } from "../../relay/__generated__/PacketsWorkspaceDetailQuery.graphql";
import {
  PacketsRoutePacketFragment,
  PacketsRouteQuery,
  PacketsWorkspaceDetailQuery
} from "./data";
import type {
  PacketConnection,
  PacketRow,
  PacketsPage,
  PacketWorkspaceDetail
} from "./types";

type PacketsWorkflowInput = {
  canPageBackward: boolean;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
  onSelectPacket: (selection: PacketSelection) => void;
  page: PacketsPage;
  fetchKey?: number;
  requestedSelection: PacketSelection | null;
};

export type PacketSelection =
  | { kind: "relay_id"; value: string }
  | { kind: "operation_id"; value: string };

type RelayPageInfo = {
  readonly endCursor: string | null | undefined;
  readonly hasNextPage: boolean;
};

export const defaultPacketsPage: PacketsPage = { first: 50, after: null };

export function usePacketsWorkflow({
  canPageBackward,
  onNextPage,
  onPreviousPage,
  onSelectPacket,
  page,
  fetchKey,
  requestedSelection
}: PacketsWorkflowInput) {
  const data = useLazyLoadQuery<PacketsRouteOperation>(PacketsRouteQuery, page, {
    fetchKey,
    fetchPolicy: "network-only"
  });
  const connection = packetConnectionFromRelay(data);
  const selectedId = selectedPacketId(connection.rows, requestedSelection);
  const selectedPacket =
    connection.rows.find((packet) => packet.id === selectedId) ?? null;

  return {
    canPageBackward,
    canCreatePacket:
      data.operatorPacketCreateAffordance.identity === "create_work_packet" &&
      data.operatorPacketCreateAffordance.state === "enabled",
    hasNextPage: connection.hasNextPage,
    loadNextPage: () => {
      if (connection.hasNextPage && connection.nextCursor !== null) {
        onNextPage(connection.nextCursor);
      }
    },
    loadPreviousPage: onPreviousPage,
    rows: connection.rows,
    selectedId,
    selectedPacket,
    selectCreatedPacket: (operationId: string) =>
      onSelectPacket({ kind: "operation_id", value: operationId }),
    selectPacket: (relayId: string) =>
      onSelectPacket({ kind: "relay_id", value: relayId })
  };
}

export function usePacketWorkspaceDetail(packetId: string, fetchKey?: number) {
  const data = useLazyLoadQuery<PacketsWorkspaceDetailOperation>(
    PacketsWorkspaceDetailQuery,
    { id: packetId },
    { fetchKey, fetchPolicy: "network-only" }
  );

  return data.operatorPacketWorkspace as PacketWorkspaceDetail;
}

export type PacketsWorkflowState = ReturnType<typeof usePacketsWorkflow>;

export function packetConnectionFromRows<TPacket>(
  rows: TPacket[],
  pageInfo: RelayPageInfo
): PacketConnection<TPacket> {
  const nextCursor = pageInfo.endCursor ?? null;

  return {
    hasNextPage: pageInfo.hasNextPage && nextCursor !== null,
    nextCursor,
    rows
  };
}

export function selectedPacketId<TPacket extends Pick<PacketRow, "id" | "operationId">>(
  rows: readonly TPacket[],
  requestedSelection: PacketSelection | null
) {
  const selectedPacket = requestedSelection
    ? rows.find((packet) =>
        requestedSelection.kind === "relay_id"
          ? packet.id === requestedSelection.value
          : packet.operationId === requestedSelection.value
      )
    : null;

  return selectedPacket?.id ?? rows[0]?.id ?? null;
}

function packetConnectionFromRelay(
  data: PacketsRouteOperation["response"]
): PacketConnection<PacketsRoutePacketFragment$data> {
  const connection = data.listWorkPackets;

  if (!connection) {
    return packetConnectionFromRows([], { endCursor: null, hasNextPage: false });
  }

  const rows = (connection.edges ?? []).flatMap((edge) => {
    if (!edge?.node) {
      return [];
    }

    return [
      readInlineData(
        PacketsRoutePacketFragment,
        edge.node as PacketsRoutePacketFragment$key
      )
    ];
  });

  return packetConnectionFromRows(rows, connection.pageInfo);
}
