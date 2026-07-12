import { readInlineData, useLazyLoadQuery } from "react-relay";
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
  runIdForItem
} from "./derived";
import type { OperatorInbox, OperatorInboxPage, PacketReadinessInput } from "./types";

type OperatorWorkflowInput = {
  fetchKey?: number;
  inboxPage: OperatorInboxPage;
  requestedSelectedId: string | null;
  selectionMode: "inbox" | "linked_run";
};

export type OperatorWorkflowItem = OperatorWorkflowItemFragment$data;
export type OperatorRunState = OperatorRunStateFragment$data;
export type PacketReadinessState =
  | OperatorPacketReadinessFragment$data
  | ReturnType<typeof packetReadinessForItem>;

export const defaultOperatorInboxPage: OperatorInboxPage = { first: 50, after: null };

export function useOperatorWorkflow({
  fetchKey,
  inboxPage,
  requestedSelectedId,
  selectionMode
}: OperatorWorkflowInput) {
  const rootData = useLazyLoadQuery<OperatorWorkflowRouteOperation>(
    OperatorWorkflowRouteQuery,
    inboxPage,
    { fetchKey, fetchPolicy: "network-only" }
  );
  const inbox = workflowConnectionFromRelay(rootData, inboxPage);
  const selectedId =
    selectionMode === "linked_run"
      ? null
      : inbox.rows.some((row) => row.normalizedEventId === requestedSelectedId)
        ? requestedSelectedId
        : (inbox.rows[0]?.normalizedEventId ?? null);
  const selectedItem =
    inbox.rows.find((row) => row.normalizedEventId === selectedId) ?? null;
  const readinessInput = selectedItem ? packetReadinessInputForItem(selectedItem) : null;
  const readiness =
    selectedItem && readinessInput
      ? packetReadinessForItem(selectedItem, readinessInput)
      : null;

  return {
    canSubmitManualIntake:
      rootData.operatorManualIntakeAffordance.identity === "submit_manual_intake" &&
      rootData.operatorManualIntakeAffordance.state === "enabled",
    inbox,
    readiness,
    readinessInput,
    rows: inbox.rows,
    runId: runIdForItem(selectedItem),
    selectedId,
    selectedItem
  };
}

export type OperatorWorkflowState = ReturnType<typeof useOperatorWorkflow>;

export function useValidatedPacketReadiness(input: PacketReadinessInput, fetchKey?: number) {
  const data = useLazyLoadQuery<OperatorPacketReadinessOperation>(
    OperatorPacketReadinessQuery,
    { input: packetReadinessQueryInput(input) },
    { fetchKey, fetchPolicy: "network-only" }
  );

  return packetReadinessFromRelay(data);
}

export function useOperatorRunState(
  runId: string,
  fetchKey?: number,
  activityAfter: string | null = null
) {
  const data = useLazyLoadQuery<OperatorRunStateOperation>(
    OperatorRunStateQuery,
    { id: runId, activityFirst: 5, activityAfter },
    { fetchKey, fetchPolicy: "network-only" }
  );

  return runStateFromRelay(data);
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
      readInlineData<OperatorWorkflowItemFragment$key>(
        OperatorWorkflowItemFragment,
        edge.node
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

  return readInlineData<OperatorRunStateFragment$key>(
    OperatorRunStateFragment,
    data.operatorRunState
  );
}

function packetReadinessFromRelay(
  data: OperatorPacketReadinessOperation["response"]
): OperatorPacketReadinessFragment$data {
  if (!data.operatorPacketReadiness) {
    throw new Error("The GraphQL packet readiness projection was empty.");
  }

  return readInlineData<OperatorPacketReadinessFragment$key>(
    OperatorPacketReadinessFragment,
    data.operatorPacketReadiness
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
