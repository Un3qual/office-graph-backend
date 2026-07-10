import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  fetchQuery,
  readInlineData,
  useLazyLoadQuery,
  useRelayEnvironment
} from "react-relay";
import type { GraphQLResponse } from "relay-runtime";
import type {
  OperatorPacketReadinessFragment$data,
  OperatorPacketReadinessFragment$key
} from "../../relay/__generated__/OperatorPacketReadinessFragment.graphql";
import type { OperatorPacketReadinessQuery as OperatorPacketReadinessOperation } from "../../relay/__generated__/OperatorPacketReadinessQuery.graphql";
import type {
  OperatorRunStateFragment$data,
  OperatorRunStateFragment$key
} from "../../relay/__generated__/OperatorRunStateFragment.graphql";
import type { OperatorRunStateQuery as OperatorRunStateOperation } from "../../relay/__generated__/OperatorRunStateQuery.graphql";
import type {
  OperatorWorkflowItemFragment$data,
  OperatorWorkflowItemFragment$key
} from "../../relay/__generated__/OperatorWorkflowItemFragment.graphql";
import type { OperatorWorkflowRouteQuery as OperatorWorkflowRouteOperation } from "../../relay/__generated__/OperatorWorkflowRouteQuery.graphql";
import {
  OperatorPacketReadinessFragment,
  OperatorPacketReadinessQuery,
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
  PacketReadinessInput,
  QueryState
} from "./types";

type PacketReadinessState =
  | OperatorPacketReadinessFragment$data
  | ReturnType<typeof packetReadinessForItem>;

type OperatorWorkflowInput = {
  inboxPage: OperatorInboxPage;
  requestedSelectedId: string | null;
};

export const defaultOperatorInboxPage: OperatorInboxPage = { first: 50, after: null };

export function useOperatorWorkflow({
  inboxPage,
  requestedSelectedId
}: OperatorWorkflowInput) {
  const relayEnvironment = useRelayEnvironment();
  const rootData = useLazyLoadQuery<OperatorWorkflowRouteOperation>(
    OperatorWorkflowRouteQuery,
    inboxPage,
    { fetchPolicy: "network-only" }
  );
  const inbox = workflowConnectionFromRelay(rootData, inboxPage);
  const selectedId = inbox.rows.some(
    (row) => row.normalizedEventId === requestedSelectedId
  )
    ? requestedSelectedId
    : (inbox.rows[0]?.normalizedEventId ?? null);
  const selectedItem =
    inbox.rows.find((row) => row.normalizedEventId === selectedId) ?? null;
  const [validatedReadinessQuery, setValidatedReadinessQuery] = useState<
    QueryState<PacketReadinessState>
  >(idleQueryState);
  const readinessValidationToken = useRef(0);
  const readinessValidationSubscription = useRef<{ unsubscribe(): void } | null>(null);
  const readinessInput = useMemo(
    () => (selectedItem ? packetReadinessInputForItem(selectedItem) : null),
    [selectedItem]
  );
  const readiness = useMemo(
    () =>
      selectedItem && readinessInput
        ? packetReadinessForItem(selectedItem, readinessInput)
        : null,
    [readinessInput, selectedItem]
  );

  useEffect(() => {
    readinessValidationToken.current += 1;
    readinessValidationSubscription.current?.unsubscribe();
    readinessValidationSubscription.current = null;
    setValidatedReadinessQuery(idleQueryState());
  }, [readinessInput, selectedId]);
  useEffect(
    () => () => {
      readinessValidationToken.current += 1;
      readinessValidationSubscription.current?.unsubscribe();
    },
    []
  );
  const readinessQuery = useMemo(() => {
    if (
      validatedReadinessQuery.data ||
      validatedReadinessQuery.isError ||
      validatedReadinessQuery.fetchStatus !== "idle"
    ) {
      return validatedReadinessQuery;
    }

    return readiness
      ? successQueryState<PacketReadinessState>(readiness)
      : idleQueryState<PacketReadinessState>();
  }, [readiness, validatedReadinessQuery]);
  const activeReadiness = validatedReadinessQuery.data ?? readiness;
  const validatePacketReadiness = useCallback(() => {
    if (!readinessInput || !readiness) {
      return;
    }

    const validationToken = readinessValidationToken.current + 1;
    readinessValidationToken.current = validationToken;
    readinessValidationSubscription.current?.unsubscribe();
    setValidatedReadinessQuery(startLoading(successQueryState(readiness)));

    readinessValidationSubscription.current = fetchQuery<OperatorPacketReadinessOperation>(
      relayEnvironment,
      OperatorPacketReadinessQuery,
      { input: packetReadinessQueryInput(readinessInput) },
      { fetchPolicy: "network-only" }
    ).subscribe({
      next: (data) => {
        if (readinessValidationToken.current === validationToken) {
          setValidatedReadinessQuery(successQueryState(packetReadinessFromRelay(data)));
        }
      },
      error: (error: unknown) => {
        if (readinessValidationToken.current === validationToken) {
          setValidatedReadinessQuery((state) => errorQueryState(state, error));
        }
      }
    });
  }, [readiness, readinessInput, relayEnvironment]);
  const runId = runIdForItem(selectedItem);
  const runStateQuery = useOperatorRunStateRelayQuery(runId);
  const verification = runStateQuery.data
    ? verificationOutcomeFromRunState(runStateQuery.data)
    : null;

  return {
    inbox,
    readiness: activeReadiness,
    readinessInput,
    readinessQuery,
    rows: inbox.rows,
    runId,
    runStateQuery,
    selectedId,
    selectedItem,
    validatePacketReadiness,
    verification
  };
}

export type OperatorWorkflowItem = OperatorWorkflowItemFragment$data;
export type OperatorWorkflowState = ReturnType<typeof useOperatorWorkflow>;

function useOperatorRunStateRelayQuery(runId: string | null) {
  const relayEnvironment = useRelayEnvironment();
  const [query, setQuery] = useState<QueryState<OperatorRunStateFragment$data>>(
    idleQueryState
  );

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
): OperatorInbox<OperatorWorkflowItemFragment$data> {
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
      )
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

function runStateFromRelay(
  data: OperatorRunStateOperation["response"]
): OperatorRunStateFragment$data {
  if (!data.operatorRunState) {
    throw new Error("The GraphQL operator run state projection was empty.");
  }

  return readInlineData(
    OperatorRunStateFragment,
    data.operatorRunState as OperatorRunStateFragment$key
  );
}

function packetReadinessFromRelay(
  data: OperatorPacketReadinessOperation["response"]
): OperatorPacketReadinessFragment$data {
  if (!data.operatorPacketReadiness) {
    throw new Error("The GraphQL packet readiness projection was empty.");
  }

  return readInlineData(
    OperatorPacketReadinessFragment,
    data.operatorPacketReadiness as OperatorPacketReadinessFragment$key
  );
}

function packetReadinessQueryInput(
  input: PacketReadinessInput
): OperatorPacketReadinessOperation["variables"]["input"] {
  return {
    title: input.title,
    objective: input.objective,
    contextSummary: input.contextSummary,
    requirements: input.requirements,
    successCriteria: input.successCriteria,
    autonomyPosture: input.autonomyPosture,
    sourceGraphItemIds: input.sourceGraphItemIds,
    verificationCheckIds: input.verificationCheckIds
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

function emptyOperatorInbox(
  page: OperatorInboxPage
): OperatorInbox<OperatorWorkflowItemFragment$data> {
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
