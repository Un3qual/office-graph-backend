import { useLazyLoadQuery } from "react-relay";
import type { RunDetailQuery as RunDetailOperation } from "../../relay/__generated__/RunDetailQuery.graphql";
import type { RunsRouteQuery as RunsRouteOperation } from "../../relay/__generated__/RunsRouteQuery.graphql";
import { RunDetailQuery, RunsRouteQuery } from "./data";
import type { RunDetailResult, RunsConnectionState, RunsPage } from "./types";

export const defaultRunsPage: RunsPage = { first: 50, after: null };
export const runActivityPageSize = 5;

export function useRunsPage(page: RunsPage, fetchKey?: number, forceNetwork = false) {
  const data = useLazyLoadQuery<RunsRouteOperation>(RunsRouteQuery, page, {
    fetchKey,
    fetchPolicy: forceNetwork ? "network-only" : "store-or-network",
  });

  return runsConnectionFromRelay(data);
}

export function useRunDetail(runId: string, fetchKey?: number): RunDetailResult {
  const data = useLazyLoadQuery<RunDetailOperation>(
    RunDetailQuery,
    {
      id: runId,
      activityFirst: runActivityPageSize,
    },
    { fetchKey, fetchPolicy: "network-only" },
  );

  if (!data.operatorRunState || !data.run) {
    throw new Error("The selected run is unavailable.");
  }

  const run = data.run;

  return {
    activityRef: data,
    detail: {
      ...data.operatorRunState,
      packet: {
        relayId: run.workPacket.id,
        title: run.workPacket.title,
      },
      packetVersion: run.workPacketVersion,
      run: {
        id: run.id,
        aggregateState: run.aggregateState,
        executionState: run.executionState,
        verificationState: run.verificationState,
      },
      requiredChecks: (run.requiredChecks.edges ?? []).flatMap((edge) =>
        edge?.node ? [edge.node] : [],
      ),
      evidenceCandidates: (run.evidenceCandidates.edges ?? []).flatMap((edge) =>
        edge?.node ? [{ ...edge.node, state: edge.node.candidateState }] : [],
      ),
      evidenceItems: (run.evidenceItems.edges ?? []).flatMap((edge) =>
        edge?.node ? [edge.node] : [],
      ),
      verificationResults: (run.verificationResults.edges ?? []).flatMap((edge) =>
        edge?.node ? [edge.node] : [],
      ),
      relationshipOverflow: {
        evidenceCandidates: run.evidenceCandidates.pageInfo.hasNextPage,
        evidenceItems: run.evidenceItems.pageInfo.hasNextPage,
        requiredChecks: run.requiredChecks.pageInfo.hasNextPage,
        verificationResults: run.verificationResults.pageInfo.hasNextPage,
      },
    },
  };
}

function runsConnectionFromRelay(data: RunsRouteOperation["response"]): RunsConnectionState {
  const connection = data.listWorkRuns;

  if (!connection) {
    return { hasNextPage: false, nextCursor: null, rows: [] };
  }

  const rows = (connection.edges ?? []).flatMap((edge) => (edge?.node ? [edge.node] : []));
  const nextCursor = connection.pageInfo.endCursor ?? null;

  return {
    hasNextPage: connection.pageInfo.hasNextPage && nextCursor !== null,
    nextCursor,
    rows,
  };
}
