import { startTransition, useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { RunList, RunListFallback, RunPageStatus } from "./components/RunList";
import { RunsRouteQuery } from "./data";
import { RunWorkspace } from "./RunWorkspace";
import type { RunsPage } from "./types";
import { defaultRunsPage, useRunsPage } from "./workflow";

type RunsNavigation = {
  page: RunsPage;
  previousCursors: Array<string | null>;
};

type PendingRunsNavigation = {
  direction: "next" | "previous";
  navigation: RunsNavigation;
};

export const routeOwnedRunsQuery = RunsRouteQuery;

export default function RunsRoute() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [listFetchKey, setListFetchKey] = useState(0);
  const [detailFetchKey, setDetailFetchKey] = useState(0);
  const [pagingFetchKey, setPagingFetchKey] = useState(0);
  const [navigation, setNavigation] = useState<RunsNavigation>({
    page: defaultRunsPage,
    previousCursors: [],
  });
  const [pendingNavigation, setPendingNavigation] = useState<PendingRunsNavigation | null>(null);
  const [isSelectionPending, setIsSelectionPending] = useState(false);
  const pendingRunIdRef = useRef<string | null>(null);
  const hasRequestedRunId = searchParams.has("runId");
  const requestedRunId = hasRequestedRunId ? (searchParams.get("runId") ?? "") : null;

  const retryList = useCallback(() => startTransition(() => setListFetchKey((key) => key + 1)), []);
  const retryDetail = useCallback(
    () => startTransition(() => setDetailFetchKey((key) => key + 1)),
    [],
  );
  const retryPage = useCallback(
    () => startTransition(() => setPagingFetchKey((key) => key + 1)),
    [],
  );

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

  const loadNextPage = useCallback(
    (nextCursor: string) => {
      setPagingFetchKey(0);
      setPendingNavigation({
        direction: "next",
        navigation: {
          page: { ...navigation.page, after: nextCursor },
          previousCursors: [...navigation.previousCursors, navigation.page.after],
        },
      });
    },
    [navigation],
  );

  const loadPreviousPage = useCallback(() => {
    const previousCursor = navigation.previousCursors.at(-1);

    if (previousCursor === undefined) {
      return;
    }

    setPagingFetchKey(0);
    setPendingNavigation({
      direction: "previous",
      navigation: {
        page: { ...navigation.page, after: previousCursor },
        previousCursors: navigation.previousCursors.slice(0, -1),
      },
    });
  }, [navigation]);

  const commitPage = useCallback((nextNavigation: RunsNavigation) => {
    setListFetchKey(0);
    setNavigation(nextNavigation);
    setPendingNavigation(null);
  }, []);

  useEffect(() => {
    if (isSelectionPending && requestedRunId === pendingRunIdRef.current) {
      pendingRunIdRef.current = null;
      setIsSelectionPending(false);
    }
  }, [isSelectionPending, requestedRunId]);

  return (
    <RunWorkspace
      detailFetchKey={detailFetchKey}
      isSelectionPending={isSelectionPending}
      list={
        <RunsListBoundary
          fetchKey={listFetchKey}
          hasRequestedRunId={hasRequestedRunId}
          navigation={navigation}
          onDefaultRun={selectDefaultRun}
          onNextPage={loadNextPage}
          onPageResolved={commitPage}
          onPreviousPage={loadPreviousPage}
          onRetry={retryList}
          onRetryPage={retryPage}
          onSelectRun={selectRun}
          pagingFetchKey={pagingFetchKey}
          pendingNavigation={pendingNavigation}
          selectedId={requestedRunId}
        />
      }
      onDetailRetry={retryDetail}
      selectedId={requestedRunId}
    />
  );
}

function RunsListBoundary({
  fetchKey,
  hasRequestedRunId,
  navigation,
  onDefaultRun,
  onNextPage,
  onPageResolved,
  onPreviousPage,
  onRetry,
  onRetryPage,
  onSelectRun,
  pagingFetchKey,
  pendingNavigation,
  selectedId,
}: {
  fetchKey: number;
  hasRequestedRunId: boolean;
  navigation: RunsNavigation;
  onDefaultRun: (id: string) => void;
  onNextPage: (cursor: string) => void;
  onPageResolved: (navigation: RunsNavigation) => void;
  onPreviousPage: () => void;
  onRetry: () => void;
  onRetryPage: () => void;
  onSelectRun: (id: string) => void;
  pagingFetchKey: number;
  pendingNavigation: PendingRunsNavigation | null;
  selectedId: string | null;
}) {
  return (
    <AsyncBoundary
      errorFallback={
        <RunListFallback
          canPageBackward={navigation.previousCursors.length > 0}
          onPreviousPage={onPreviousPage}
          onRetry={onRetry}
          state="error"
        />
      }
      loadingFallback={
        <RunListFallback
          canPageBackward={navigation.previousCursors.length > 0}
          onPreviousPage={onPreviousPage}
          state="initial-loading"
        />
      }
      resetKey={`runs:${navigation.page.after ?? "initial"}:${fetchKey}`}
    >
      <LoadedRunsList
        fetchKey={fetchKey}
        hasRequestedRunId={hasRequestedRunId}
        navigation={navigation}
        onDefaultRun={onDefaultRun}
        onNextPage={onNextPage}
        onPageResolved={onPageResolved}
        onPreviousPage={onPreviousPage}
        onRetryPage={onRetryPage}
        onSelectRun={onSelectRun}
        pagingFetchKey={pagingFetchKey}
        pendingNavigation={pendingNavigation}
        selectedId={selectedId}
      />
    </AsyncBoundary>
  );
}

function LoadedRunsList({
  fetchKey,
  hasRequestedRunId,
  navigation,
  onDefaultRun,
  onNextPage,
  onPageResolved,
  onPreviousPage,
  onRetryPage,
  onSelectRun,
  pagingFetchKey,
  pendingNavigation,
  selectedId,
}: {
  fetchKey: number;
  hasRequestedRunId: boolean;
  navigation: RunsNavigation;
  onDefaultRun: (id: string) => void;
  onNextPage: (cursor: string) => void;
  onPageResolved: (navigation: RunsNavigation) => void;
  onPreviousPage: () => void;
  onRetryPage: () => void;
  onSelectRun: (id: string) => void;
  pagingFetchKey: number;
  pendingNavigation: PendingRunsNavigation | null;
  selectedId: string | null;
}) {
  const connection = useRunsPage(navigation.page, fetchKey, fetchKey > 0);

  useEffect(() => {
    const defaultRunId = connection.rows[0]?.id;

    if (!hasRequestedRunId && defaultRunId) {
      onDefaultRun(defaultRunId);
    }
  }, [connection.rows, hasRequestedRunId, onDefaultRun]);

  const pageAttempt = pendingNavigation ? (
    <AsyncBoundary
      errorFallback={
        <RunPageStatus
          direction={pendingNavigation.direction}
          onRetry={onRetryPage}
          state="error"
        />
      }
      loadingFallback={<RunPageStatus direction={pendingNavigation.direction} state="loading" />}
      resetKey={`${pendingNavigation.navigation.page.after ?? "initial"}:${pagingFetchKey}`}
    >
      <PendingRunPage
        fetchKey={pagingFetchKey}
        navigation={pendingNavigation.navigation}
        onResolved={onPageResolved}
      />
    </AsyncBoundary>
  ) : null;

  return (
    <RunList
      canPageBackward={navigation.previousCursors.length > 0}
      hasNextPage={connection.hasNextPage}
      isPaging={pendingNavigation !== null}
      onNextPage={() => {
        if (connection.nextCursor !== null) {
          onNextPage(connection.nextCursor);
        }
      }}
      onPreviousPage={onPreviousPage}
      onSelect={onSelectRun}
      pageAttempt={pageAttempt}
      rows={connection.rows}
      selectedId={selectedId}
    />
  );
}

function PendingRunPage({
  fetchKey,
  navigation,
  onResolved,
}: {
  fetchKey: number;
  navigation: RunsNavigation;
  onResolved: (navigation: RunsNavigation) => void;
}) {
  useRunsPage(navigation.page, fetchKey, true);

  useEffect(() => {
    onResolved(navigation);
  }, [navigation, onResolved]);

  return null;
}
