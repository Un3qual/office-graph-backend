import { startTransition, useCallback, useState } from "react";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { PacketsRouteQuery } from "./data";
import {
  PacketWorkspace,
  PacketWorkspaceError,
  PacketWorkspaceLoading
} from "./PacketWorkspace";
import type { PacketsPage } from "./types";
import {
  defaultPacketsPage,
  type PacketSelection,
  usePacketsWorkflow
} from "./workflow";

type PacketNavigation = {
  hasNavigated: boolean;
  page: PacketsPage;
  previousCursors: Array<string | null>;
};

type PacketsRouteContentProps = {
  canPageBackward: boolean;
  fetchKey: number;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
  onRefresh: () => void;
  onSelectPacket: (selection: PacketSelection) => void;
  page: PacketsPage;
  requestedSelection: PacketSelection | null;
};

export const routeOwnedPacketQuery = PacketsRouteQuery;

export default function PacketsRoute() {
  const [fetchKey, setFetchKey] = useState(0);
  const refresh = useCallback(() => startTransition(() => setFetchKey(key => key + 1)), []);
  const [navigation, setNavigation] = useState<PacketNavigation>({
    hasNavigated: false,
    page: defaultPacketsPage,
    previousCursors: []
  });
  const [requestedSelection, setRequestedSelection] = useState<PacketSelection | null>(null);

  const loadNextPage = (nextCursor: string) => {
    setRequestedSelection(null);
    setNavigation(({ page, previousCursors }) => ({
      hasNavigated: true,
      page: page.after === nextCursor ? page : { ...page, after: nextCursor },
      previousCursors:
        page.after === nextCursor ? previousCursors : [...previousCursors, page.after]
    }));
  };

  const loadPreviousPage = () => {
    setRequestedSelection(null);
    setNavigation(({ page, previousCursors }) => {
      if (previousCursors.length === 0) {
        return { hasNavigated: true, page, previousCursors };
      }

      return {
        hasNavigated: true,
        page: {
          ...page,
          after: previousCursors[previousCursors.length - 1] ?? null
        },
        previousCursors: previousCursors.slice(0, -1)
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
        onSelectPacket={setRequestedSelection}
        page={navigation.page}
        requestedSelection={requestedSelection}
      />
    </AsyncBoundary>
  );
}

function PacketsRouteContent(props: PacketsRouteContentProps) {
  const workflow = usePacketsWorkflow(props);

  return (
    <PacketWorkspace
      {...workflow}
      fetchKey={props.fetchKey}
      onRefresh={props.onRefresh}
    />
  );
}
