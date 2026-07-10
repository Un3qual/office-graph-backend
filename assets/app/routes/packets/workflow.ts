import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchQuery, readInlineData, useRelayEnvironment } from "react-relay";
import type {
  PacketsRoutePacketFragment$data,
  PacketsRoutePacketFragment$key
} from "../../relay/__generated__/PacketsRoutePacketFragment.graphql";
import type { PacketsRouteQuery as PacketsRouteOperation } from "../../relay/__generated__/PacketsRouteQuery.graphql";
import { PacketsRoutePacketFragment, PacketsRouteQuery } from "./data";
import type { PacketConnection, PacketsPage, QueryState } from "./types";

export const defaultPacketsPage: PacketsPage = { first: 50, after: null };

export function usePacketsWorkflow() {
  const relayEnvironment = useRelayEnvironment();
  const [navigation, setNavigation] = useState({
    page: defaultPacketsPage,
    previousCursors: [] as Array<string | null>
  });
  const [packetQuery, setPacketQuery] =
    useState<QueryState<PacketConnection<PacketsRoutePacketFragment$data>>>(idleQueryState);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const page = navigation.page;

  useEffect(() => {
    let isCurrent = true;

    setPacketQuery(startLoading);

    const subscription = fetchQuery<PacketsRouteOperation>(
      relayEnvironment,
      PacketsRouteQuery,
      page,
      { fetchPolicy: "network-only" }
    ).subscribe({
      next: (data) => {
        if (isCurrent) {
          setPacketQuery(successQueryState(packetConnectionFromRelay(data, page)));
        }
      },
      error: () => {
        if (isCurrent) {
          setPacketQuery((state) => errorQueryState(state));
        }
      }
    });

    return () => {
      isCurrent = false;
      subscription.unsubscribe();
    };
  }, [page, relayEnvironment]);

  useEffect(() => {
    if (!packetQuery.data) {
      return;
    }

    const rowIds = new Set(packetQuery.data.rows.map((packet) => packet.id));
    const firstId = packetQuery.data.rows[0]?.id ?? null;

    if (selectedId === null || !rowIds.has(selectedId)) {
      setSelectedId(firstId);
    }
  }, [packetQuery.data, selectedId]);

  const selectPacket = useCallback((id: string) => {
    setSelectedId(id);
  }, []);

  const loadNextPage = useCallback(() => {
    const nextCursor = packetQuery.data?.hasNextPage
      ? packetQuery.data.nextCursor
      : null;

    if (nextCursor !== null) {
      setNavigation(({ page: currentPage, previousCursors }) => {
        if (currentPage.after === nextCursor) {
          return { page: currentPage, previousCursors };
        }

        return {
          page: { ...currentPage, after: nextCursor },
          previousCursors: [...previousCursors, currentPage.after]
        };
      });
    }
  }, [packetQuery.data?.hasNextPage, packetQuery.data?.nextCursor]);

  const loadPreviousPage = useCallback(() => {
    setNavigation(({ page: currentPage, previousCursors }) => {
      if (previousCursors.length === 0) {
        return { page: currentPage, previousCursors };
      }

      const nextPreviousCursors = previousCursors.slice(0, -1);
      const previousCursor = previousCursors[previousCursors.length - 1] ?? null;

      return {
        page: { ...currentPage, after: previousCursor },
        previousCursors: nextPreviousCursors
      };
    });
  }, []);

  const rows = packetQuery.data?.rows ?? [];
  const selectedPacket = useMemo(
    () => rows.find((packet) => packet.id === selectedId) ?? null,
    [rows, selectedId]
  );

  return {
    canPageBackward: navigation.previousCursors.length > 0,
    loadNextPage,
    loadPreviousPage,
    packetPage: page,
    packetQuery,
    rows,
    selectedId,
    selectedPacket,
    selectPacket
  };
}

export type PacketsWorkflowState = ReturnType<typeof usePacketsWorkflow>;

function packetConnectionFromRelay(
  data: PacketsRouteOperation["response"],
  page: PacketsPage
): PacketConnection<PacketsRoutePacketFragment$data> {
  const connection = data.listWorkPackets;

  if (!connection) {
    return emptyPacketConnection(page);
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

  return {
    after: page.after,
    empty: rows.length === 0,
    first: page.first,
    hasNextPage: connection.pageInfo.hasNextPage,
    hasPreviousPage: connection.pageInfo.hasPreviousPage,
    nextCursor: connection.pageInfo.endCursor ?? null,
    startCursor: connection.pageInfo.startCursor ?? null,
    rows
  };
}

function emptyPacketConnection(
  page: PacketsPage
): PacketConnection<PacketsRoutePacketFragment$data> {
  return {
    after: page.after,
    empty: true,
    first: page.first,
    hasNextPage: false,
    hasPreviousPage: false,
    nextCursor: null,
    startCursor: null,
    rows: []
  };
}

function idleQueryState<T>(): QueryState<T> {
  return {
    data: null,
    error: null,
    fetchStatus: "idle",
    isError: false,
    isPending: false,
    isSuccess: false
  };
}

function startLoading<T>(state: QueryState<T>): QueryState<T> {
  return {
    ...state,
    error: null,
    fetchStatus: "fetching",
    isError: false,
    isPending: state.data === null,
    isSuccess: state.data !== null
  };
}

function successQueryState<T>(data: T): QueryState<T> {
  return {
    data,
    error: null,
    fetchStatus: "idle",
    isError: false,
    isPending: false,
    isSuccess: true
  };
}

function errorQueryState<T>(state: QueryState<T>): QueryState<T> {
  return {
    ...state,
    error: new Error("Unable to load packets."),
    fetchStatus: "idle",
    isError: true,
    isPending: false,
    isSuccess: false
  };
}
