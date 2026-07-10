import { useState } from "react";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { PacketsRouteQuery } from "./data";
import {
  PacketWorkspace,
  PacketWorkspaceError,
  PacketWorkspaceLoading
} from "./PacketWorkspace";
import type { PacketsPage } from "./types";
import { defaultPacketsPage, usePacketsWorkflow } from "./workflow";

type PacketNavigation = {
  hasNavigated: boolean;
  page: PacketsPage;
  previousCursors: Array<string | null>;
};

type PacketsRouteContentProps = {
  canPageBackward: boolean;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
  onSelectPacket: (id: string) => void;
  page: PacketsPage;
  requestedSelectedId: string | null;
};

export const routeOwnedPacketQuery = PacketsRouteQuery;

export default function PacketsRoute() {
  const [navigation, setNavigation] = useState<PacketNavigation>({
    hasNavigated: false,
    page: defaultPacketsPage,
    previousCursors: []
  });
  const [requestedSelectedId, setRequestedSelectedId] = useState<string | null>(null);

  const loadNextPage = (nextCursor: string) => {
    setRequestedSelectedId(null);
    setNavigation(({ page, previousCursors }) => ({
      hasNavigated: true,
      page: page.after === nextCursor ? page : { ...page, after: nextCursor },
      previousCursors:
        page.after === nextCursor ? previousCursors : [...previousCursors, page.after]
    }));
  };

  const loadPreviousPage = () => {
    setRequestedSelectedId(null);
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
      errorFallback={<PacketWorkspaceError />}
      loadingFallback={<PacketWorkspaceLoading isPage={navigation.hasNavigated} />}
      resetKey={`packets:${navigation.page.after ?? "initial"}`}
    >
      <PacketsRouteContent
        canPageBackward={navigation.previousCursors.length > 0}
        onNextPage={loadNextPage}
        onPreviousPage={loadPreviousPage}
        onSelectPacket={setRequestedSelectedId}
        page={navigation.page}
        requestedSelectedId={requestedSelectedId}
      />
    </AsyncBoundary>
  );
}

function PacketsRouteContent(props: PacketsRouteContentProps) {
  const workflow = usePacketsWorkflow(props);

  return <PacketWorkspace {...workflow} />;
}
