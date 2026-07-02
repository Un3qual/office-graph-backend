import { useQuery } from "@tanstack/react-query";
import {
  operatorInboxQuery,
  operatorItemQuery,
  operatorPacketReadinessQuery,
  operatorRunStateQuery
} from "./workflowGraphql";
import {
  graphQLInbox,
  graphQLItem,
  graphQLPacketReadiness,
  graphQLRunState
} from "./workflowMappers";
import type {
  GraphQLFetcher,
  OperatorInboxPage,
  OperatorInbox,
  OperatorRunState,
  OperatorWorkflowItem,
  PacketReadiness,
  PacketReadinessInput
} from "./workflowTypes";

const emptyPacketReadinessInput: PacketReadinessInput = {
  title: "",
  objective: "",
  contextSummary: "",
  requirements: "",
  successCriteria: "",
  autonomyPosture: "",
  sourceGraphItemIds: [],
  verificationCheckIds: []
};

export const operatorQueryKeys = {
  inbox: (page: OperatorInboxPage) =>
    ["operator", "workflow", "inbox", page.limit, page.offset] as const,
  item: (normalizedEventId: string) =>
    ["operator", "workflow", "item", normalizedEventId] as const,
  packetReadiness: (input: PacketReadinessInput) =>
    [
      "operator",
      "workflow",
      "packetReadiness",
      input.title,
      input.objective,
      input.contextSummary,
      input.requirements,
      input.successCriteria,
      input.autonomyPosture,
      sortedIds(input.sourceGraphItemIds).join(","),
      sortedIds(input.verificationCheckIds).join(",")
    ] as const,
  runState: (runId: string) => ["operator", "workflow", "runState", runId] as const
};

export async function fetchOperatorInbox(
  fetchGraphQL: GraphQLFetcher,
  page: OperatorInboxPage = defaultOperatorInboxPage,
  signal?: AbortSignal
): Promise<OperatorInbox> {
  const data = await requestGraphQL(fetchGraphQL, operatorInboxQuery, page, signal);

  return graphQLInbox(data.operatorInbox);
}

export async function fetchOperatorItem(
  fetchGraphQL: GraphQLFetcher,
  normalizedEventId: string,
  signal?: AbortSignal
): Promise<OperatorWorkflowItem> {
  const data = await requestGraphQL(fetchGraphQL, operatorItemQuery, { id: normalizedEventId }, signal);

  return graphQLItem(data.operatorWorkflowItem);
}

export async function fetchPacketReadiness(
  fetchGraphQL: GraphQLFetcher,
  input: PacketReadinessInput,
  signal?: AbortSignal
): Promise<PacketReadiness> {
  const data = await requestGraphQL(fetchGraphQL, operatorPacketReadinessQuery, { input }, signal);

  return graphQLPacketReadiness(data.operatorPacketReadiness);
}

export async function fetchOperatorRunState(
  fetchGraphQL: GraphQLFetcher,
  runId: string,
  signal?: AbortSignal
): Promise<OperatorRunState> {
  const data = await requestGraphQL(fetchGraphQL, operatorRunStateQuery, { id: runId }, signal);

  return graphQLRunState(data.operatorRunState);
}

export function useOperatorInboxQuery(fetchGraphQL: GraphQLFetcher, page: OperatorInboxPage) {
  return useQuery({
    queryKey: operatorQueryKeys.inbox(page),
    queryFn: ({ signal }) => fetchOperatorInbox(fetchGraphQL, page, signal)
  });
}

export function useOperatorItemQuery(
  fetchGraphQL: GraphQLFetcher,
  normalizedEventId: string | null,
  enabled: boolean
) {
  return useQuery({
    enabled: enabled && Boolean(normalizedEventId),
    queryKey: normalizedEventId
      ? operatorQueryKeys.item(normalizedEventId)
      : ["operator", "workflow", "item", "none"],
    queryFn: ({ signal }) => fetchOperatorItem(fetchGraphQL, normalizedEventId ?? "", signal)
  });
}

export function usePacketReadinessQuery(
  fetchGraphQL: GraphQLFetcher,
  input: PacketReadinessInput | null,
  enabled: boolean
) {
  return useQuery({
    enabled: enabled && Boolean(input),
    queryKey: input
      ? operatorQueryKeys.packetReadiness(input)
      : ["operator", "workflow", "packetReadiness", "none"],
    queryFn: ({ signal }) =>
      fetchPacketReadiness(
        fetchGraphQL,
        input ?? emptyPacketReadinessInput,
        signal
      )
  });
}

export function useOperatorRunStateQuery(
  fetchGraphQL: GraphQLFetcher,
  runId: string | null,
  enabled: boolean
) {
  return useQuery({
    enabled: enabled && Boolean(runId),
    queryKey: runId ? operatorQueryKeys.runState(runId) : ["operator", "workflow", "runState", "none"],
    queryFn: ({ signal }) => fetchOperatorRunState(fetchGraphQL, runId ?? "", signal)
  });
}

async function requestGraphQL(
  fetchGraphQL: GraphQLFetcher,
  query: string,
  variables: Record<string, unknown>,
  signal?: AbortSignal
) {
  const request = signal ? { query, variables, signal } : { query, variables };
  const response = await fetchGraphQL(request);

  if (response.errors?.length) {
    throw new Error(response.errors[0]?.message ?? "The GraphQL operator request failed.");
  }

  if (!response.data) {
    throw new Error("The GraphQL operator response did not include data.");
  }

  return response.data;
}

function sortedIds(ids: string[]) {
  return [...ids].sort();
}

export const defaultOperatorInboxPage: OperatorInboxPage = { limit: 50, offset: 0 };
