import { useCallback, useEffect, useMemo, useState } from "react";
import { packetReadinessInputForItem, runIdForItem } from "./workflowDerived";
import { verificationOutcomeFromRunState } from "./workflowMappers";
import {
  defaultOperatorInboxPage,
  useOperatorInboxQuery,
  useOperatorItemQuery,
  useOperatorRunStateQuery,
  usePacketReadinessQuery
} from "./workflowQueries";
import type { GraphQLFetcher, OperatorWorkflowItem } from "./workflowTypes";

export function useOperatorWorkflow(fetchGraphQL: GraphQLFetcher) {
  const [inboxNavigation, setInboxNavigation] = useState({
    page: defaultOperatorInboxPage,
    previousCursors: [] as Array<string | null>
  });
  const inboxPage = inboxNavigation.page;
  const inboxQuery = useOperatorInboxQuery(fetchGraphQL, inboxPage);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [selectedSource, setSelectedSource] = useState<"inbox" | "external">("inbox");

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

  const selectItem = useCallback((id: string) => {
    setSelectedId(id);
    setSelectedSource("external");
  }, []);

  const loadNextInboxPage = useCallback(() => {
    const nextCursor = inboxQuery.data?.nextCursor ?? null;

    if (nextCursor !== null) {
      setInboxNavigation(({ page, previousCursors }) => ({
        page: page.afterCursor === nextCursor ? page : { ...page, afterCursor: nextCursor },
        previousCursors:
          page.afterCursor === nextCursor ? previousCursors : [...previousCursors, page.afterCursor]
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
        page: { ...page, afterCursor: previousCursor },
        previousCursors: nextPreviousCursors
      };
    });
  }, []);

  const selectedInboxItem = useMemo(
    () => inboxQuery.data?.rows.find((row) => row.normalizedEventId === selectedId) ?? null,
    [inboxQuery.data, selectedId]
  );

  const itemQuery = useOperatorItemQuery(fetchGraphQL, selectedId, Boolean(selectedId && !selectedInboxItem));
  const selectedItem = selectedInboxItem ?? itemQuery.data ?? null;
  const readinessInput = selectedItem ? packetReadinessInputForItem(selectedItem) : null;
  const readinessQuery = usePacketReadinessQuery(fetchGraphQL, readinessInput, Boolean(selectedItem));
  const runId = runIdForItem(selectedItem);
  const runStateQuery = useOperatorRunStateQuery(fetchGraphQL, runId, Boolean(runId));
  const verification = runStateQuery.data ? verificationOutcomeFromRunState(runStateQuery.data) : null;

  return {
    canPageBackward: inboxNavigation.previousCursors.length > 0,
    inboxQuery,
    inboxPage,
    itemQuery,
    loadNextInboxPage,
    loadPreviousInboxPage,
    readiness: readinessQuery.data ?? null,
    readinessInput,
    readinessQuery,
    rows: inboxQuery.data?.rows ?? [],
    runId,
    runStateQuery,
    selectedId,
    selectedItem: selectedItem as OperatorWorkflowItem | null,
    selectInboxItem,
    selectItem,
    verification
  };
}

export type OperatorWorkflowState = ReturnType<typeof useOperatorWorkflow>;
