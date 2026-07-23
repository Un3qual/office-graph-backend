import { startTransition, useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { RunListFallback } from "./components/RunList";
import { RunDetail } from "./components/RunDetail";
import { RunsLayout } from "./components/RunsLayout";
import { RunsRouteQuery } from "./data";
import { RunWorkspace } from "./RunWorkspace";
import type { RunsPage } from "./types";
import { defaultRunsPage, useRunsPage } from "./workflow";

type RunsNavigation = {
  page: RunsPage;
  previousCursors: Array<string | null>;
};

export const routeOwnedRunsQuery = RunsRouteQuery;

export default function RunsRoute() {
  const [listFetchKey, setListFetchKey] = useState(0);
  const [detailFetchKey, setDetailFetchKey] = useState(0);
  const [navigation, setNavigation] = useState<RunsNavigation>({
    page: defaultRunsPage,
    previousCursors: [],
  });
  const retryList = useCallback(() => startTransition(() => setListFetchKey((key) => key + 1)), []);
  const retryDetail = useCallback(
    () => startTransition(() => setDetailFetchKey((key) => key + 1)),
    [],
  );

  const loadNextPage = useCallback((nextCursor: string) => {
    setNavigation(({ page, previousCursors }) => ({
      page: page.after === nextCursor ? page : { ...page, after: nextCursor },
      previousCursors:
        page.after === nextCursor ? previousCursors : [...previousCursors, page.after],
    }));
  }, []);

  const loadPreviousPage = useCallback(() => {
    setNavigation(({ page, previousCursors }) => {
      const previousCursor = previousCursors.at(-1);

      if (previousCursor === undefined) {
        return { page, previousCursors };
      }

      return {
        page: { ...page, after: previousCursor },
        previousCursors: previousCursors.slice(0, -1),
      };
    });
  }, []);

  return (
    <AsyncBoundary
      errorFallback={
        <RunsLayout
          detail={<RunDetail selectedId={null} state="empty" />}
          list={
            <RunListFallback
              canPageBackward={navigation.previousCursors.length > 0}
              onPreviousPage={loadPreviousPage}
              onRetry={retryList}
              state="error"
            />
          }
        />
      }
      loadingFallback={
        <RunsLayout
          detail={<RunDetail selectedId={null} state="empty" />}
          list={
            <RunListFallback
              canPageBackward={navigation.previousCursors.length > 0}
              onPreviousPage={loadPreviousPage}
              state={navigation.page.after === null ? "initial-loading" : "page-loading"}
            />
          }
        />
      }
      resetKey={`runs:${navigation.page.after ?? "initial"}:${listFetchKey}`}
    >
      <RunsRouteContent
        detailFetchKey={detailFetchKey}
        listFetchKey={listFetchKey}
        navigation={navigation}
        onDetailRetry={retryDetail}
        onNextPage={loadNextPage}
        onPreviousPage={loadPreviousPage}
      />
    </AsyncBoundary>
  );
}

function RunsRouteContent({
  detailFetchKey,
  listFetchKey,
  navigation,
  onDetailRetry,
  onNextPage,
  onPreviousPage,
}: {
  detailFetchKey: number;
  listFetchKey: number;
  navigation: RunsNavigation;
  onDetailRetry: () => void;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
}) {
  const connection = useRunsPage(navigation.page, listFetchKey);

  return (
    <RunsSelectionContent
      connection={connection}
      detailFetchKey={detailFetchKey}
      navigation={navigation}
      onDetailRetry={onDetailRetry}
      onNextPage={onNextPage}
      onPreviousPage={onPreviousPage}
    />
  );
}

function RunsSelectionContent({
  connection,
  detailFetchKey,
  navigation,
  onDetailRetry,
  onNextPage,
  onPreviousPage,
}: {
  connection: ReturnType<typeof useRunsPage>;
  detailFetchKey: number;
  navigation: RunsNavigation;
  onDetailRetry: () => void;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
}) {
  const [searchParams, setSearchParams] = useSearchParams();
  const [isSelectionPending, setIsSelectionPending] = useState(false);
  const pendingRunIdRef = useRef<string | null>(null);
  const hasRequestedRunId = searchParams.has("runId");
  const requestedRunId = hasRequestedRunId ? (searchParams.get("runId") ?? "") : null;
  const selectedId = hasRequestedRunId ? requestedRunId : (connection.rows[0]?.id ?? null);
  const selectRun = useCallback(
    (id: string) => {
      pendingRunIdRef.current = id;
      setIsSelectionPending(true);
      setSearchParams(
        (currentSearchParams) => {
          const nextSearchParams = new URLSearchParams(currentSearchParams);
          nextSearchParams.set("runId", id);
          return nextSearchParams;
        },
        { flushSync: true },
      );
    },
    [setSearchParams],
  );
  const selectDefaultRun = useCallback(
    (id: string) => {
      setSearchParams(
        (currentSearchParams) => {
          if (currentSearchParams.has("runId")) {
            return currentSearchParams;
          }

          const nextSearchParams = new URLSearchParams(currentSearchParams);
          nextSearchParams.set("runId", id);
          return nextSearchParams;
        },
        { flushSync: true, replace: true },
      );
    },
    [setSearchParams],
  );

  useEffect(() => {
    if (!hasRequestedRunId && selectedId !== null) {
      selectDefaultRun(selectedId);
    }
  }, [hasRequestedRunId, selectDefaultRun, selectedId]);

  useEffect(() => {
    if (isSelectionPending && requestedRunId === pendingRunIdRef.current) {
      pendingRunIdRef.current = null;
      setIsSelectionPending(false);
    }
  }, [isSelectionPending, requestedRunId]);

  return (
    <RunWorkspace
      canPageBackward={navigation.previousCursors.length > 0}
      detailFetchKey={detailFetchKey}
      hasNextPage={connection.hasNextPage}
      isSelectionPending={isSelectionPending}
      loadNextPage={() => {
        if (connection.nextCursor !== null) {
          onNextPage(connection.nextCursor);
        }
      }}
      loadPreviousPage={onPreviousPage}
      onDetailRetry={onDetailRetry}
      onSelectRun={selectRun}
      rows={connection.rows}
      selectedId={selectedId}
    />
  );
}
