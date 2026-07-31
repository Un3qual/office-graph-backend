import { readInlineData, useLazyLoadQuery } from "react-relay";
import type {
  OperatorPacketReadinessFragment$data,
  OperatorPacketReadinessFragment$key,
} from "../../relay/__generated__/OperatorPacketReadinessFragment.graphql";
import type { OperatorPacketReadinessQuery as OperatorPacketReadinessOperation } from "../../relay/__generated__/OperatorPacketReadinessQuery.graphql";
import type { OperatorRunConversationQuery as OperatorRunConversationOperation } from "../../relay/__generated__/OperatorRunConversationQuery.graphql";
import type {
  OperatorRunStateFragment$data,
  OperatorRunStateFragment$key,
} from "../../relay/__generated__/OperatorRunStateFragment.graphql";
import type { OperatorRunStateQuery as OperatorRunStateOperation } from "../../relay/__generated__/OperatorRunStateQuery.graphql";
import type {
  OperatorWorkflowItemFragment$data,
  OperatorWorkflowItemFragment$key,
} from "../../relay/__generated__/OperatorWorkflowItemFragment.graphql";
import type { OperatorWorkflowRouteQuery as OperatorWorkflowRouteOperation } from "../../relay/__generated__/OperatorWorkflowRouteQuery.graphql";
import { relayGlobalId, relayInternalId } from "../../relay/relayIds";
import {
  OperatorPacketReadinessFragment,
  OperatorPacketReadinessQuery,
  OperatorRunConversationQuery,
  OperatorRunStateFragment,
  OperatorRunStateQuery,
  OperatorWorkflowItemFragment,
  OperatorWorkflowRouteQuery,
} from "./data";
import {
  packetReadinessForItem,
  packetReadinessInputForItem,
  primarySourceGraphItemIdForItem,
  runIdForItem,
} from "./derived";
import type { OperatorInbox, OperatorInboxPage, PacketReadinessInput } from "./types";

const agentHistoryLimit = 100;

type OperatorWorkflowInput = {
  fetchKey?: number;
  inboxPage: OperatorInboxPage;
  requestedSelectedId: string | null;
  selectionMode: "inbox" | "linked_run";
};

export type OperatorWorkflowItem = OperatorWorkflowItemFragment$data;
type OperatorRunResource = NonNullable<OperatorRunStateOperation["response"]["run"]>;
type OperatorRunConnectionNode<
  TConnection extends { readonly edges?: ReadonlyArray<unknown> | null },
> = NonNullable<NonNullable<TConnection["edges"]>[number]> extends {
  readonly node: infer TNode;
}
  ? NonNullable<TNode>
  : never;

export type OperatorRunState = OperatorRunStateFragment$data & {
  packet: OperatorRunResource["workPacket"];
  packetVersion: OperatorRunResource["workPacketVersion"];
  run: Pick<OperatorRunResource, "id" | "aggregateState" | "executionState" | "verificationState">;
  requiredChecks: Array<OperatorRunConnectionNode<OperatorRunResource["requiredChecks"]>>;
  observations: Array<OperatorRunConnectionNode<OperatorRunResource["executionObservations"]>>;
  evidenceCandidates: Array<
    Omit<OperatorRunConnectionNode<OperatorRunResource["evidenceCandidates"]>, "candidateState"> & {
      state: string;
    }
  >;
  evidenceItems: Array<OperatorRunConnectionNode<OperatorRunResource["evidenceItems"]>>;
  verificationResults: Array<OperatorRunConnectionNode<OperatorRunResource["verificationResults"]>>;
};
export type OperatorRunConversation = ReturnType<typeof runConversationFromRelay>;
export type PacketReadinessState =
  | OperatorPacketReadinessFragment$data
  | ReturnType<typeof packetReadinessForItem>;

export const defaultOperatorInboxPage: OperatorInboxPage = { first: 50, after: null };

export function useOperatorWorkflow({
  fetchKey,
  inboxPage,
  requestedSelectedId,
  selectionMode,
}: OperatorWorkflowInput) {
  const rootData = useLazyLoadQuery<OperatorWorkflowRouteOperation>(
    OperatorWorkflowRouteQuery,
    inboxPage,
    { fetchKey, fetchPolicy: "network-only" },
  );
  const inbox = workflowConnectionFromRelay(rootData, inboxPage);
  const selectedId =
    selectionMode === "linked_run"
      ? null
      : inbox.rows.some((row) => row.normalizedEventId === requestedSelectedId)
        ? requestedSelectedId
        : (inbox.rows[0]?.normalizedEventId ?? null);
  const selectedItem = inbox.rows.find((row) => row.normalizedEventId === selectedId) ?? null;
  const readinessInput = selectedItem ? packetReadinessInputForItem(selectedItem) : null;
  const readiness =
    selectedItem && readinessInput ? packetReadinessForItem(selectedItem, readinessInput) : null;
  const primarySourceGraphItemId = selectedItem
    ? primarySourceGraphItemIdForItem(selectedItem)
    : null;

  return {
    canSubmitManualIntake:
      rootData.operatorManualIntakeAffordance.identity === "submit_manual_intake" &&
      rootData.operatorManualIntakeAffordance.state === "enabled",
    inbox,
    primarySourceGraphItemId,
    readiness,
    readinessInput,
    rows: inbox.rows,
    runId: runIdForItem(selectedItem),
    selectedId,
    selectedItem,
  };
}

export type OperatorWorkflowState = ReturnType<typeof useOperatorWorkflow>;

export function useValidatedPacketReadiness(input: PacketReadinessInput, fetchKey?: number) {
  const data = useLazyLoadQuery<OperatorPacketReadinessOperation>(
    OperatorPacketReadinessQuery,
    { input: packetReadinessQueryInput(input) },
    { fetchKey, fetchPolicy: "network-only" },
  );

  return packetReadinessFromRelay(data);
}

export function useOperatorRunState(
  runId: string,
  fetchKey?: number,
  activityAfter: string | null = null,
) {
  const projectionId = relayInternalId("work_run", runId);
  const data = useLazyLoadQuery<OperatorRunStateOperation>(
    OperatorRunStateQuery,
    {
      projectionId,
      runId: relayGlobalId("work_run", projectionId),
      activityFirst: 5,
      activityAfter,
    },
    { fetchKey, fetchPolicy: "network-only" },
  );

  return runStateFromRelay(data);
}

export function useOperatorRunConversation(runId: string, graphItemId: string, fetchKey?: number) {
  const internalRunId = relayInternalId("work_run", runId);
  const internalGraphItemId = relayInternalId("graph_item", graphItemId);
  const data = useLazyLoadQuery<OperatorRunConversationOperation>(
    OperatorRunConversationQuery,
    {
      runId: internalRunId,
      graphItemId: internalGraphItemId,
      runRelayId: relayGlobalId("work_run", internalRunId),
      graphItemRelayId: relayGlobalId("graph_item", internalGraphItemId),
    },
    { fetchKey, fetchPolicy: "network-only" },
  );

  return runConversationFromRelay(data);
}

function runConversationFromRelay(data: OperatorRunConversationOperation["response"]) {
  const projection = data.operatorRunConversation;
  const contextByMessageId = new Map(
    projection.messageContexts.map((context) => [context.messageId, context.referencedContext]),
  );
  const conversation = data.conversation;
  const executions = conversation
    ? prioritizedConnectionNodes(data.activeAgentExecutions, data.terminalAgentExecutions).sort(
        compareInsertedAt,
      )
    : [];
  const approvalRequests = conversation
    ? prioritizedConnectionNodes(
        data.pendingAgentApprovalRequests,
        data.resolvedAgentApprovalRequests,
      )
        .sort(compareInsertedAt)
        .map((request) => ({ ...request, executionId: request.execution.id }))
    : [];
  const contextExpansionRequests = conversation
    ? prioritizedConnectionNodes(
        data.pendingAgentContextExpansionRequests,
        data.resolvedAgentContextExpansionRequests,
      )
        .sort(compareInsertedAt)
        .map((request) => ({ ...request, executionId: request.execution.id }))
    : [];

  return {
    ...projection,
    conversation: conversation
      ? {
          id: conversation.id,
          runId: conversation.run.id,
          graphItemId: conversation.graphItem.id,
          state: conversation.state,
          stateVersion: conversation.stateVersion,
        }
      : null,
    messages: conversation
      ? connectionNodes(conversation.messages)
          .reverse()
          .map((message) => ({
            id: message.id,
            source: message.source,
            body: message.body,
            executionId: message.execution?.id ?? null,
            insertedAt: message.insertedAt,
            referencedContext: contextByMessageId.get(message.id) ?? null,
          }))
      : [],
    executions,
    approvalRequests,
    contextExpansionRequests,
  };
}

function connectionNodes<T>(
  connection:
    | {
        readonly edges?: ReadonlyArray<{ readonly node: T }> | null;
      }
    | null
    | undefined,
): T[] {
  return (connection?.edges ?? []).map((edge) => edge.node);
}

function prioritizedConnectionNodes<T>(
  priority: Parameters<typeof connectionNodes<T>>[0],
  history: Parameters<typeof connectionNodes<T>>[0],
) {
  const priorityNodes = connectionNodes(priority);
  const remaining = Math.max(agentHistoryLimit - priorityNodes.length, 0);

  return priorityNodes.concat(connectionNodes(history).slice(0, remaining));
}

function compareInsertedAt(
  left: { readonly insertedAt: string },
  right: { readonly insertedAt: string },
) {
  return left.insertedAt.localeCompare(right.insertedAt);
}

function workflowConnectionFromRelay(
  data: OperatorWorkflowRouteOperation["response"],
  page: OperatorInboxPage,
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
      readInlineData<OperatorWorkflowItemFragment$key>(OperatorWorkflowItemFragment, edge.node),
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
    rows,
  };
}

function runStateFromRelay(data: OperatorRunStateOperation["response"]): OperatorRunState {
  if (!data.operatorRunState || !data.run) {
    throw new Error("The GraphQL operator run state read was empty.");
  }

  const projection = readInlineData<OperatorRunStateFragment$key>(
    OperatorRunStateFragment,
    data.operatorRunState,
  );
  const run = data.run;

  return {
    ...projection,
    packet: run.workPacket,
    packetVersion: run.workPacketVersion,
    run: {
      id: run.id,
      aggregateState: run.aggregateState,
      executionState: run.executionState,
      verificationState: run.verificationState,
    },
    requiredChecks: (run.requiredChecks.edges ?? []).map(({ node }) => node),
    observations: (run.executionObservations.edges ?? []).map(({ node }) => node),
    evidenceCandidates: (run.evidenceCandidates.edges ?? []).map(
      ({ node: { candidateState, ...candidate } }) => ({
        ...candidate,
        state: candidateState,
      }),
    ),
    evidenceItems: (run.evidenceItems.edges ?? []).map(({ node }) => node),
    verificationResults: (run.verificationResults.edges ?? []).map(({ node }) => node),
  };
}

function packetReadinessFromRelay(
  data: OperatorPacketReadinessOperation["response"],
): OperatorPacketReadinessFragment$data {
  if (!data.operatorPacketReadiness) {
    throw new Error("The GraphQL packet readiness projection was empty.");
  }

  return readInlineData<OperatorPacketReadinessFragment$key>(
    OperatorPacketReadinessFragment,
    data.operatorPacketReadiness,
  );
}

function packetReadinessQueryInput(
  input: PacketReadinessInput,
): OperatorPacketReadinessOperation["variables"]["input"] {
  return {
    title: input.title,
    objective: input.objective,
    contextSummary: input.contextSummary,
    requirements: input.requirements,
    successCriteria: input.successCriteria,
    autonomyPosture: input.autonomyPosture,
    sourceGraphItemIds: input.sourceGraphItemIds,
    verificationCheckIds: input.verificationCheckIds,
  };
}

function emptyOperatorInbox(
  page: OperatorInboxPage,
): OperatorInbox<OperatorWorkflowItemFragment$data> {
  return {
    type: "operator_inbox",
    empty: true,
    hasMore: false,
    limit: page.first,
    nextCursor: null,
    afterCursor: page.after,
    sourceWatermark: null,
    rows: [],
  };
}
