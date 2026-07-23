import { readInlineData, useLazyLoadQuery } from "react-relay";
import type {
  PacketsRoutePacketFragment$data,
  PacketsRoutePacketFragment$key,
} from "../../relay/__generated__/PacketsRoutePacketFragment.graphql";
import type { PacketsRouteQuery as PacketsRouteOperation } from "../../relay/__generated__/PacketsRouteQuery.graphql";
import type { PacketsWorkspaceDetailQuery as PacketsWorkspaceDetailOperation } from "../../relay/__generated__/PacketsWorkspaceDetailQuery.graphql";
import { PacketsRoutePacketFragment, PacketsRouteQuery, PacketsWorkspaceDetailQuery } from "./data";
import type { PacketConnection, PacketRow, PacketsPage, PacketWorkspaceDetail } from "./types";

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
  | { kind: "packet_id"; value: string }
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
  requestedSelection,
}: PacketsWorkflowInput) {
  const createdOperationId =
    requestedSelection?.kind === "operation_id" ? requestedSelection.value : null;
  const packetId = requestedSelection?.kind === "packet_id" ? requestedSelection.value : "";
  const data = useLazyLoadQuery<PacketsRouteOperation>(
    PacketsRouteQuery,
    {
      ...page,
      createdOperationId,
      loadCreatedPacket: createdOperationId !== null,
      packetId,
      loadLinkedPacket: packetId !== "",
    },
    {
      fetchKey,
      fetchPolicy: "network-only",
    },
  );
  const connection = packetConnectionFromRelay(data);
  const rows = mergePacket(
    mergePacket(connection.rows, packetRowsFromRelayConnection(data.createdPacket)[0] ?? null),
    data.linkedPacket
      ? readInlineData<PacketsRoutePacketFragment$key>(
          PacketsRoutePacketFragment,
          data.linkedPacket,
        )
      : null,
  );
  const selectedId = selectedPacketId(rows, requestedSelection);
  const selectedPacket = rows.find((packet) => packet.id === selectedId) ?? null;

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
    rows,
    selectedId,
    selectedPacket,
    selectCreatedPacket: (operationId: string) =>
      onSelectPacket({ kind: "operation_id", value: operationId }),
    selectPacket: (relayId: string) => onSelectPacket({ kind: "relay_id", value: relayId }),
  };
}

export function usePacketWorkspaceDetail(
  packetId: string,
  versionPage: PacketsPage,
  fetchKey?: number,
) {
  const data = useLazyLoadQuery<PacketsWorkspaceDetailOperation>(
    PacketsWorkspaceDetailQuery,
    { id: packetId, versionFirst: versionPage.first, versionAfter: versionPage.after },
    { fetchKey, fetchPolicy: "network-only" },
  );

  const workspace = data.operatorPacketWorkspace;
  const versions = (workspace.versionHistory?.edges ?? []).flatMap((edge) =>
    edge?.node ? [edge.node] : [],
  );

  const detail: PacketWorkspaceDetail = {
    ...workspace,
    versions,
    versionPageInfo: workspace.versionHistory?.pageInfo ?? {
      hasNextPage: false,
      hasPreviousPage: false,
      startCursor: null,
      endCursor: null,
    },
  };

  return detail;
}

export type PacketsWorkflowState = ReturnType<typeof usePacketsWorkflow>;

export function packetConnectionFromRows<TPacket>(
  rows: TPacket[],
  pageInfo: RelayPageInfo,
): PacketConnection<TPacket> {
  const nextCursor = pageInfo.endCursor ?? null;

  return {
    hasNextPage: pageInfo.hasNextPage && nextCursor !== null,
    nextCursor,
    rows,
  };
}

export function selectedPacketId<TPacket extends Pick<PacketRow, "id" | "operationId">>(
  rows: readonly TPacket[],
  requestedSelection: PacketSelection | null,
) {
  const selectedPacket = requestedSelection
    ? rows.find((packet) =>
        requestedSelection.kind === "operation_id"
          ? packet.operationId === requestedSelection.value
          : packet.id === requestedSelection.value,
      )
    : null;

  if (selectedPacket) {
    return selectedPacket.id;
  }

  return requestedSelection?.kind === "operation_id" || requestedSelection?.kind === "packet_id"
    ? null
    : (rows[0]?.id ?? null);
}

function packetConnectionFromRelay(
  data: PacketsRouteOperation["response"],
): PacketConnection<PacketsRoutePacketFragment$data> {
  const connection = data.listWorkPackets;

  if (!connection) {
    return packetConnectionFromRows([], { endCursor: null, hasNextPage: false });
  }

  return packetConnectionFromRows(packetRowsFromRelayConnection(connection), connection.pageInfo);
}

type PacketRelayConnection = {
  readonly edges?: ReadonlyArray<{
    readonly node?: PacketsRoutePacketFragment$key | null;
  } | null> | null;
};

function packetRowsFromRelayConnection(
  connection: PacketRelayConnection | null | undefined,
): PacketsRoutePacketFragment$data[] {
  return (connection?.edges ?? []).flatMap((edge) => {
    if (!edge?.node) {
      return [];
    }

    return [readInlineData<PacketsRoutePacketFragment$key>(PacketsRoutePacketFragment, edge.node)];
  });
}

function mergePacket<TPacket extends Pick<PacketRow, "id">>(
  rows: readonly TPacket[],
  packet: TPacket | null,
): TPacket[] {
  if (!packet || rows.some((row) => row.id === packet.id)) {
    return [...rows];
  }

  return [packet, ...rows];
}
