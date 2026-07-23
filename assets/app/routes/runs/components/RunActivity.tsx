import { useCallback, useEffect, useRef, useState } from "react";
import { AsyncBoundary } from "../../../../src/ui/AsyncBoundary";
import { Button } from "../../../../src/ui/Button";
import type { RunDetailState } from "../types";
import { useRunDetail } from "../workflow";
import { formatLabel } from "./RunList";

type ActivityPage = NonNullable<RunDetailState["activity"]>;

type ActivityRequest = {
  after: string;
  fetchKey: number;
};

export function RunActivity({
  activity,
  runId,
}: {
  activity: RunDetailState["activity"];
  runId: string;
}) {
  const [requests, setRequests] = useState<ActivityRequest[]>([]);
  const [nextCursor, setNextCursor] = useState(() => nextActivityCursor(activity));
  const requestedCursorsRef = useRef(new Set<string>());
  const loadMore = useCallback(() => {
    if (nextCursor === null || requestedCursorsRef.current.has(nextCursor)) {
      return;
    }

    requestedCursorsRef.current.add(nextCursor);
    setRequests((currentRequests) => [...currentRequests, { after: nextCursor, fetchKey: 0 }]);
    setNextCursor(null);
  }, [nextCursor]);
  const retry = useCallback((after: string) => {
    setRequests((currentRequests) =>
      currentRequests.map((request) =>
        request.after === after ? { ...request, fetchKey: request.fetchKey + 1 } : request,
      ),
    );
  }, []);
  const resolve = useCallback((_after: string, page: ActivityPage) => {
    setNextCursor(nextActivityCursor(page));
  }, []);

  return (
    <section aria-label="Run activity" className="runs-activity">
      <div className="runs-section-heading">
        <h3>Recent activity</h3>
        <span>5 events per page</span>
      </div>
      <ActivityRows activity={activity} empty />
      {requests.map((request, index) => (
        <AsyncBoundary
          errorFallback={
            <div role="alert">
              <p>Unable to load more activity.</p>
              <Button onPress={() => retry(request.after)}>Retry activity</Button>
            </div>
          }
          key={request.after}
          loadingFallback={<p role="status">Loading more activity...</p>}
          resetKey={`${runId}:${request.after}:${request.fetchKey}`}
        >
          <LoadedActivityPage
            after={request.after}
            fetchKey={request.fetchKey}
            onResolved={index === requests.length - 1 ? resolve : undefined}
            runId={runId}
          />
        </AsyncBoundary>
      ))}
      {nextCursor !== null ? <Button onPress={loadMore}>Load more activity</Button> : null}
    </section>
  );
}

function LoadedActivityPage({
  after,
  fetchKey,
  onResolved,
  runId,
}: {
  after: string;
  fetchKey: number;
  onResolved?: (after: string, page: ActivityPage) => void;
  runId: string;
}) {
  const detail = useRunDetail(runId, fetchKey, after);
  const activity = detail.activity;

  useEffect(() => {
    if (activity && onResolved) {
      onResolved(after, activity);
    }
  }, [activity, after, onResolved]);

  return <ActivityRows activity={activity} />;
}

function ActivityRows({
  activity,
  empty = false,
}: {
  activity: RunDetailState["activity"];
  empty?: boolean;
}) {
  const edges = activity?.edges ?? [];

  return edges.length === 0 ? (
    empty ? (
      <p>No activity is available for this run.</p>
    ) : null
  ) : (
    <ol>
      {edges.flatMap((edge) =>
        edge?.node
          ? [
              <li key={`${edge.node.kind}:${edge.node.stableId}`}>
                <span>{edge.node.title}</span>
                <BadgeText value={edge.node.status} />
              </li>,
            ]
          : [],
      )}
    </ol>
  );
}

function nextActivityCursor(activity: RunDetailState["activity"]) {
  const cursor = activity?.pageInfo.endCursor ?? null;

  return activity?.pageInfo.hasNextPage && cursor !== null ? cursor : null;
}

function BadgeText({ value }: { value: string }) {
  return <span className="runs-activity-state">{formatLabel(value)}</span>;
}
