import { startTransition, useCallback, useEffect, useState } from "react";
import { useSearchParams } from "react-router";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { PacketsRouteQuery } from "./data";
import { PacketWorkspace, PacketWorkspaceError, PacketWorkspaceLoading } from "./PacketWorkspace";
import type { PacketsPage } from "./types";
import { defaultPacketsPage, type PacketSelection, usePacketsWorkflow } from "./workflow";

type PacketNavigation = {
  hasNavigated: boolean;
  page: PacketsPage;
  previousCursors: Array<string | null>;
};

type LocalPacketSelection = {
  origin: "default" | "explicit" | "operation";
  pageAfter?: string | null;
  selection: PacketSelection;
};

type PacketsRouteContentProps = {
  canPageBackward: boolean;
  fetchKey: number;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
  onRefresh: () => void;
  onSelectDefaultPacket: (id: string) => void;
  onSelectPacket: (selection: PacketSelection) => void;
  page: PacketsPage;
  requestedSelection: PacketSelection | null;
};

export const routeOwnedPacketQuery = PacketsRouteQuery;

export default function PacketsRoute() {
  const [searchParams, setSearchParams] = useSearchParams();
  const packetId = searchParams.has("packetId") ? (searchParams.get("packetId") ?? "") : null;
  const [fetchKey, setFetchKey] = useState(0);
  const refresh = useCallback(() => startTransition(() => setFetchKey((key) => key + 1)), []);
  const [navigation, setNavigation] = useState<PacketNavigation>({
    hasNavigated: false,
    page: defaultPacketsPage,
    previousCursors: [],
  });
  const [localSelection, setLocalSelection] = useState<LocalPacketSelection | null>(null);
  const requestedSelection: PacketSelection | null =
    packetId !== null
      ? localSelection?.origin === "default" &&
        localSelection.pageAfter !== navigation.page.after &&
        localSelection.selection.value === packetId
        ? null
        : localSelection?.origin === "default" &&
            localSelection.selection.kind === "relay_id" &&
            localSelection.selection.value === packetId
          ? localSelection.selection
          : { kind: "packet_id", value: packetId }
      : localSelection?.selection.kind === "operation_id"
        ? localSelection.selection
        : null;

  const selectPacket = (selection: PacketSelection) => {
    if (selection.kind === "relay_id") {
      setLocalSelection({
        origin: "explicit",
        selection: { kind: "packet_id", value: selection.value },
      });
      setSearchParams((currentSearchParams) => {
        const nextSearchParams = new URLSearchParams(currentSearchParams);
        nextSearchParams.set("packetId", selection.value);
        return nextSearchParams;
      });
      return;
    }

    if (selection.kind === "operation_id") {
      setLocalSelection({ origin: "operation", selection });
      setSearchParams((currentSearchParams) => {
        const nextSearchParams = new URLSearchParams(currentSearchParams);
        nextSearchParams.delete("packetId");
        return nextSearchParams;
      });
      setNavigation({
        hasNavigated: false,
        page: defaultPacketsPage,
        previousCursors: [],
      });
    }
  };

  const selectDefaultPacket = useCallback(
    (id: string) => {
      setLocalSelection({
        origin: "default",
        pageAfter: navigation.page.after,
        selection: { kind: "relay_id", value: id },
      });
      setSearchParams(
        (currentSearchParams) => {
          const nextSearchParams = new URLSearchParams(currentSearchParams);
          nextSearchParams.set("packetId", id);
          return nextSearchParams;
        },
        { replace: true },
      );
    },
    [navigation.page.after, setSearchParams],
  );

  const loadNextPage = (nextCursor: string) => {
    if (localSelection?.origin === "operation") {
      setLocalSelection(null);
    }

    setNavigation(({ page, previousCursors }) => ({
      hasNavigated: true,
      page: page.after === nextCursor ? page : { ...page, after: nextCursor },
      previousCursors:
        page.after === nextCursor ? previousCursors : [...previousCursors, page.after],
    }));
  };

  const loadPreviousPage = () => {
    if (localSelection?.origin === "operation") {
      setLocalSelection(null);
    }

    setNavigation(({ page, previousCursors }) => {
      if (previousCursors.length === 0) {
        return { hasNavigated: true, page, previousCursors };
      }

      return {
        hasNavigated: true,
        page: {
          ...page,
          after: previousCursors[previousCursors.length - 1] ?? null,
        },
        previousCursors: previousCursors.slice(0, -1),
      };
    });
  };

  return (
    <AsyncBoundary
      errorFallback={
        <PacketWorkspaceError
          canPageBackward={navigation.previousCursors.length > 0}
          onRetry={refresh}
          onPreviousPage={loadPreviousPage}
        />
      }
      loadingFallback={<PacketWorkspaceLoading isPage={navigation.hasNavigated} />}
      resetKey={`packets:${navigation.page.after ?? "initial"}:${fetchKey}`}
    >
      <PacketsRouteContent
        canPageBackward={navigation.previousCursors.length > 0}
        fetchKey={fetchKey}
        onNextPage={loadNextPage}
        onPreviousPage={loadPreviousPage}
        onRefresh={refresh}
        onSelectDefaultPacket={selectDefaultPacket}
        onSelectPacket={selectPacket}
        page={navigation.page}
        requestedSelection={requestedSelection}
      />
    </AsyncBoundary>
  );
}

function PacketsRouteContent(props: PacketsRouteContentProps) {
  const workflow = usePacketsWorkflow(props);
  const { onSelectDefaultPacket, requestedSelection } = props;

  useEffect(() => {
    if (requestedSelection === null && workflow.selectedId !== null) {
      onSelectDefaultPacket(workflow.selectedId);
    }
  }, [onSelectDefaultPacket, requestedSelection, workflow.selectedId]);

  return <PacketWorkspace {...workflow} fetchKey={props.fetchKey} onRefresh={props.onRefresh} />;
}
