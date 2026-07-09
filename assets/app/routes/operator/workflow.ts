import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchQuery, readInlineData, useRelayEnvironment } from "react-relay";
import type { GraphQLResponse } from "relay-runtime";
import type { OperatorRunStateFragment$key } from "../../relay/__generated__/OperatorRunStateFragment.graphql";
import type { OperatorRunStateQuery as OperatorRunStateOperation } from "../../relay/__generated__/OperatorRunStateQuery.graphql";
import type { OperatorWorkflowItemFragment$key } from "../../relay/__generated__/OperatorWorkflowItemFragment.graphql";
import type { OperatorWorkflowRouteQuery as OperatorWorkflowRouteOperation } from "../../relay/__generated__/OperatorWorkflowRouteQuery.graphql";
import {
  OperatorRunStateFragment,
  OperatorRunStateQuery,
  OperatorWorkflowItemFragment,
  OperatorWorkflowRouteQuery
} from "./data";
import {
  packetReadinessInputForItem,
  packetReadinessForItem,
  runIdForItem,
  verificationOutcomeFromRunState
} from "./derived";
import type {
  OperatorInbox,
  OperatorInboxPage,
  OperatorRunState,
  OperatorWorkflowItem,
  PacketReadiness,
  PacketReadinessInput,
  QueryState
} from "./types";

export const defaultOperatorInboxPage: OperatorInboxPage = { first: 50, after: null };

export function useOperatorWorkflow() {
  const relayEnvironment = useRelayEnvironment();
  const [inboxNavigation, setInboxNavigation] = useState({
    page: defaultOperatorInboxPage,
    previousCursors: [] as Array<string | null>
  });
  const inboxPage = inboxNavigation.page;
  const [inboxQuery, setInboxQuery] = useState<QueryState<OperatorInbox>>(idleQueryState);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [selectedSource, setSelectedSource] = useState<"inbox" | "external">("inbox");

  useEffect(() => {
    let isCurrent = true;

    setInboxQuery(startLoading);

    const subscription = fetchQuery<OperatorWorkflowRouteOperation>(
      relayEnvironment,
      OperatorWorkflowRouteQuery,
      inboxPage,
      { fetchPolicy: "network-only" }
    ).subscribe({
      next: (data) => {
        if (isCurrent) {
          setInboxQuery(successQueryState(workflowConnectionFromRelay(data, inboxPage)));
        }
      },
      error: (error: unknown) => {
        if (isCurrent) {
          setInboxQuery((state) => errorQueryState(state, error));
        }
      }
    });

    return () => {
      isCurrent = false;
      subscription.unsubscribe();
    };
  }, [inboxPage, relayEnvironment]);

  useEffect(() => {
    if (!inboxQuery.data) {
      return;
    }

    const rowIds = new Set(inboxQuery.data.rows.map((row) => row.normalizedEventId));
    const firstId = inboxQuery.data.rows[0]?.normalizedEventId ?? null;

    if (selectedId === null) {
      setSelectedId(firstId);
      setSelectedSource("inbox");
    } else if (selectedSource === "inbox" && firstId === null) {
      setSelectedId(null);
      setSelectedSource("inbox");
    } else if (selectedSource === "inbox" && !rowIds.has(selectedId)) {
      setSelectedId(firstId);
      setSelectedSource("inbox");
    }
  }, [inboxQuery.data, selectedId, selectedSource]);

  const selectInboxItem = useCallback((id: string) => {
    setSelectedId(id);
    setSelectedSource("inbox");
  }, []);

  const loadNextInboxPage = useCallback(() => {
    const nextCursor = inboxQuery.data?.nextCursor ?? null;

    if (nextCursor !== null) {
      setInboxNavigation(({ page, previousCursors }) => ({
        page: page.after === nextCursor ? page : { ...page, after: nextCursor },
        previousCursors:
          page.after === nextCursor ? previousCursors : [...previousCursors, page.after]
      }));
    }
  }, [inboxQuery.data?.nextCursor]);

  const loadPreviousInboxPage = useCallback(() => {
    setInboxNavigation(({ page, previousCursors }) => {
      if (previousCursors.length === 0) {
        return { page, previousCursors };
      }

      const nextPreviousCursors = previousCursors.slice(0, -1);
      const previousCursor = previousCursors[previousCursors.length - 1] ?? null;

      return {
        page: { ...page, after: previousCursor },
        previousCursors: nextPreviousCursors
      };
    });
  }, []);

  const selectedInboxItem = useMemo(
    () => inboxQuery.data?.rows.find((row) => row.normalizedEventId === selectedId) ?? null,
    [inboxQuery.data, selectedId]
  );
  const selectedItem = selectedInboxItem;
  const readinessInput = useMemo(
    () => (selectedItem ? packetReadinessInputForItem(selectedItem) : null),
    [selectedItem]
  );
  const readiness = useMemo(
    () => (selectedItem && readinessInput ? packetReadinessForItem(selectedItem, readinessInput) : null),
    [readinessInput, selectedItem]
  );
  const readinessQuery = useMemo(
    () =>
      readiness
        ? successQueryState<PacketReadiness>(readiness)
        : idleQueryState<PacketReadiness>(),
    [readiness]
  );
  const runId = runIdForItem(selectedItem);
  const runStateQuery = useOperatorRunStateRelayQuery(runId);
  const verification = runStateQuery.data ? verificationOutcomeFromRunState(runStateQuery.data) : null;

  return {
    canPageBackward: inboxNavigation.previousCursors.length > 0,
    inboxQuery,
    inboxPage,
    itemQuery: idleQueryState<OperatorWorkflowItem>(),
    loadNextInboxPage,
    loadPreviousInboxPage,
    readiness,
    readinessInput,
    readinessQuery,
    rows: inboxQuery.data?.rows ?? [],
    runId,
    runStateQuery,
    selectedId,
    selectedItem,
    selectInboxItem,
    verification
  };
}

export type OperatorWorkflowState = ReturnType<typeof useOperatorWorkflow>;

function useOperatorRunStateRelayQuery(runId: string | null) {
  const relayEnvironment = useRelayEnvironment();
  const [query, setQuery] = useState<QueryState<OperatorRunState>>(idleQueryState);

  useEffect(() => {
    if (!runId) {
      setQuery(idleQueryState());
      return;
    }

    let isCurrent = true;

    setQuery(loadingQueryState());

    const subscription = fetchQuery<OperatorRunStateOperation>(
      relayEnvironment,
      OperatorRunStateQuery,
      { id: runId },
      { fetchPolicy: "network-only" }
    ).subscribe({
      next: (data) => {
        if (isCurrent) {
          setQuery(successQueryState(runStateFromRelay(data)));
        }
      },
      error: (error: unknown) => {
        if (isCurrent) {
          setQuery((state) => errorQueryState(state, error));
        }
      }
    });

    return () => {
      isCurrent = false;
      subscription.unsubscribe();
    };
  }, [relayEnvironment, runId]);

  return query;
}

function workflowConnectionFromRelay(
  data: OperatorWorkflowRouteOperation["response"],
  page: OperatorInboxPage
): OperatorInbox {
  const connection = data.operatorWorkflowItems;

  if (!connection) {
    return emptyOperatorInbox(page);
  }

  const rows = (connection.edges ?? []).flatMap((edge) => {
    if (!edge?.node) {
      return [];
    }

    return [
      readInlineData(
        OperatorWorkflowItemFragment,
        edge.node as OperatorWorkflowItemFragment$key
      ) as OperatorWorkflowItem
    ];
  });

  return {
    type: "operator_inbox",
    empty: rows.length === 0,
    hasMore: connection.pageInfo.hasNextPage,
    limit: page.first,
    nextCursor: connection.pageInfo.endCursor ?? null,
    afterCursor: page.after,
    sourceWatermark: rows[0]?.sourceWatermark ?? null,
    rows
  };
}

function runStateFromRelay(data: OperatorRunStateOperation["response"]): OperatorRunState {
  if (!data.operatorRunState) {
    throw new Error("The GraphQL operator run state projection was empty.");
  }

  return readInlineData(
    OperatorRunStateFragment,
    data.operatorRunState as OperatorRunStateFragment$key
  ) as OperatorRunState;
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

function loadingQueryState<T>(): QueryState<T> {
  return {
    data: null,
    error: null,
    fetchStatus: "fetching",
    isError: false,
    isPending: true,
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

function emptyOperatorInbox(page: OperatorInboxPage): OperatorInbox {
  return {
    type: "operator_inbox",
    empty: true,
    hasMore: false,
    limit: page.first,
    nextCursor: null,
    afterCursor: page.after,
    sourceWatermark: null,
    rows: []
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

function errorQueryState<T>(state: QueryState<T>, error: unknown): QueryState<T> {
  return {
    ...state,
    error: normalizeRelayError(error),
    fetchStatus: "idle",
    isError: true,
    isPending: false,
    isSuccess: false
  };
}

function normalizeRelayError(error: unknown) {
  if (error instanceof Error) {
    return error;
  }

  const graphQLError = firstGraphQLError(error);

  return new Error(graphQLError ?? "The GraphQL operator request failed.");
}

function firstGraphQLError(error: unknown) {
  if (typeof error !== "object" || error === null || !("source" in error)) {
    return null;
  }

  const source = (error as { source?: GraphQLResponse }).source;
  const firstError = source && "errors" in source ? source.errors?.[0] : null;

  return typeof firstError?.message === "string" ? firstError.message : null;
}
