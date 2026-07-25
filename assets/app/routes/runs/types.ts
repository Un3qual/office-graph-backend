import type { RunActivityFragment$key } from "../../relay/__generated__/RunActivityFragment.graphql";
import type { RunDetailQuery as RunDetailOperation } from "../../relay/__generated__/RunDetailQuery.graphql";
import type { RunsRouteQuery as RunsRouteOperation } from "../../relay/__generated__/RunsRouteQuery.graphql";

type RunsConnection = NonNullable<RunsRouteOperation["response"]["operatorRuns"]>;
type RunsEdge = NonNullable<NonNullable<RunsConnection["edges"]>[number]>;

export type RunSummary = NonNullable<RunsEdge["node"]>;
export type RunDetailState = NonNullable<RunDetailOperation["response"]["operatorRunState"]>;
export type RunDetailResult = {
  activityRef: RunActivityFragment$key;
  detail: RunDetailState;
};

export type RunsPage = {
  first: number;
  after: string | null;
};

export type RunsConnectionState = {
  hasNextPage: boolean;
  nextCursor: string | null;
  rows: RunSummary[];
};
