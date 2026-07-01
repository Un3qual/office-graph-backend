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
  OperatorInbox,
  OperatorRunState,
  OperatorWorkflowItem,
  PacketReadiness,
  PacketReadinessInput
} from "./workflowTypes";

export const operatorQueryKeys = {
  inbox: () => ["operator", "workflow", "inbox"] as const,
  item: (normalizedEventId: string) =>
    ["operator", "workflow", "item", normalizedEventId] as const,
  packetReadiness: (input: PacketReadinessInput) =>
    [
      "operator",
      "workflow",
      "packetReadiness",
      input.sourceGraphItemIds.join(","),
      input.verificationCheckIds.join(",")
    ] as const,
  runState: (runId: string) => ["operator", "workflow", "runState", runId] as const
};

export async function fetchOperatorInbox(fetchGraphQL: GraphQLFetcher): Promise<OperatorInbox> {
  const data = await requestGraphQL(fetchGraphQL, operatorInboxQuery, {});

  return graphQLInbox(data.operatorInbox);
}

export async function fetchOperatorItem(
  fetchGraphQL: GraphQLFetcher,
  normalizedEventId: string
): Promise<OperatorWorkflowItem> {
  const data = await requestGraphQL(fetchGraphQL, operatorItemQuery, { id: normalizedEventId });

  return graphQLItem(data.operatorWorkflowItem);
}

export async function fetchPacketReadiness(
  fetchGraphQL: GraphQLFetcher,
  input: PacketReadinessInput
): Promise<PacketReadiness> {
  const data = await requestGraphQL(fetchGraphQL, operatorPacketReadinessQuery, { input });

  return graphQLPacketReadiness(data.operatorPacketReadiness);
}

export async function fetchOperatorRunState(
  fetchGraphQL: GraphQLFetcher,
  runId: string
): Promise<OperatorRunState> {
  const data = await requestGraphQL(fetchGraphQL, operatorRunStateQuery, { id: runId });

  return graphQLRunState(data.operatorRunState);
}

export function useOperatorInboxQuery(fetchGraphQL: GraphQLFetcher) {
  return useQuery({
    queryKey: operatorQueryKeys.inbox(),
    queryFn: () => fetchOperatorInbox(fetchGraphQL)
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
    queryFn: () => fetchOperatorItem(fetchGraphQL, normalizedEventId ?? "")
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
    queryFn: () =>
      fetchPacketReadiness(fetchGraphQL, input ?? { sourceGraphItemIds: [], verificationCheckIds: [] })
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
    queryFn: () => fetchOperatorRunState(fetchGraphQL, runId ?? "")
  });
}

async function requestGraphQL(
  fetchGraphQL: GraphQLFetcher,
  query: string,
  variables: Record<string, unknown>
) {
  const response = await fetchGraphQL({ query, variables });

  if (response.errors?.length) {
    throw new Error(response.errors[0]?.message ?? "The GraphQL operator request failed.");
  }

  if (!response.data) {
    throw new Error("The GraphQL operator response did not include data.");
  }

  return response.data;
}
