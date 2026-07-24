import { useLazyLoadQuery } from "react-relay";
import type { RunActivityPageQuery as RunActivityPageOperation } from "../../relay/__generated__/RunActivityPageQuery.graphql";
import type { RunDetailQuery as RunDetailOperation } from "../../relay/__generated__/RunDetailQuery.graphql";
import type { RunsRouteQuery as RunsRouteOperation } from "../../relay/__generated__/RunsRouteQuery.graphql";
import { RunActivityPageQuery, RunDetailQuery, RunsRouteQuery } from "./data";
import type { RunDetailState, RunsConnectionState, RunsPage } from "./types";

export const defaultRunsPage: RunsPage = { first: 50, after: null };

export function useRunsPage(page: RunsPage, fetchKey?: number, forceNetwork = false) {
  const data = useLazyLoadQuery<RunsRouteOperation>(RunsRouteQuery, page, {
    fetchKey,
    fetchPolicy: forceNetwork ? "network-only" : "store-or-network",
  });

  return runsConnectionFromRelay(data);
}

export function useRunDetail(
  runId: string,
  fetchKey?: number,
  activityAfter: string | null = null,
): RunDetailState {
  const data = useLazyLoadQuery<RunDetailOperation>(
    RunDetailQuery,
    {
      id: runId,
      activityFirst: 5,
      activityAfter,
    },
    { fetchKey, fetchPolicy: "network-only" },
  );

  if (!data.operatorRunState) {
    throw new Error("The selected run is unavailable.");
  }

  return data.operatorRunState;
}

export function useRunActivityPage(
  runId: string,
  after: string,
  fetchKey?: number,
): RunDetailState["activity"] {
  const data = useLazyLoadQuery<RunActivityPageOperation>(
    RunActivityPageQuery,
    {
      id: runId,
      activityFirst: 5,
      activityAfter: after,
    },
    { fetchKey, fetchPolicy: "network-only" },
  );

  if (!data.operatorRunState) {
    throw new Error("The selected run is unavailable.");
  }

  return data.operatorRunState.activity;
}

function runsConnectionFromRelay(data: RunsRouteOperation["response"]): RunsConnectionState {
  const connection = data.operatorRuns;

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
