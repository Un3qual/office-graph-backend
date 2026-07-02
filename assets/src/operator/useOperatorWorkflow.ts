import { useEffect, useMemo, useState } from "react";
import { packetReadinessInputForItem, runIdForItem } from "./workflowDerived";
import { verificationOutcomeFromRunState } from "./workflowMappers";
import {
  useOperatorInboxQuery,
  useOperatorItemQuery,
  useOperatorRunStateQuery,
  usePacketReadinessQuery
} from "./workflowQueries";
import type { GraphQLFetcher, OperatorWorkflowItem } from "./workflowTypes";

export function useOperatorWorkflow(fetchGraphQL: GraphQLFetcher) {
  const inboxQuery = useOperatorInboxQuery(fetchGraphQL);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    if (!inboxQuery.data) {
      return;
    }

    const firstId = inboxQuery.data.rows[0]?.normalizedEventId ?? null;
    const selectedExists = inboxQuery.data.rows.some((row) => row.normalizedEventId === selectedId);

    if (!selectedId || !selectedExists) {
      setSelectedId(firstId);
    }
  }, [inboxQuery.data, selectedId]);

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
    inboxQuery,
    itemQuery,
    readiness: readinessQuery.data ?? null,
    readinessQuery,
    rows: inboxQuery.data?.rows ?? [],
    runId,
    runStateQuery,
    selectedId,
    selectedItem: selectedItem as OperatorWorkflowItem | null,
    selectItem: setSelectedId,
    verification
  };
}

export type OperatorWorkflowState = ReturnType<typeof useOperatorWorkflow>;
