import { useCallback, useState } from "react";
import { usePaginationFragment } from "react-relay";
import { Button } from "../../../../src/ui/Button";
import type {
  RunActivityFragment$data,
  RunActivityFragment$key,
} from "../../../relay/__generated__/RunActivityFragment.graphql";
import { RunActivityFragment } from "../data";
import { runActivityPageSize } from "../workflow";
import { formatLabel } from "./RunList";

type Activity = RunActivityFragment$data["operatorRunState"]["activity"];

export function RunActivity({ activityRef }: { activityRef: RunActivityFragment$key }) {
  const { data, hasNext, isLoadingNext, loadNext } = usePaginationFragment(
    RunActivityFragment,
    activityRef,
  );
  const [loadFailed, setLoadFailed] = useState(false);
  const loadMore = useCallback(() => {
    if (!hasNext || isLoadingNext) {
      return;
    }

    setLoadFailed(false);
    loadNext(runActivityPageSize, {
      onComplete: (error) => setLoadFailed(error !== null),
    });
  }, [hasNext, isLoadingNext, loadNext]);

  return (
    <section aria-label="Run activity" className="runs-activity">
      <div className="runs-section-heading">
        <h3>Recent activity</h3>
        <span>{runActivityPageSize} events per page</span>
      </div>
      <ActivityRows activity={data.operatorRunState.activity} empty />
      {isLoadingNext ? <p role="status">Loading more activity...</p> : null}
      {loadFailed ? (
        <div role="alert">
          <p>Unable to load more activity.</p>
          <Button onPress={loadMore}>Retry activity</Button>
        </div>
      ) : null}
      {hasNext && !isLoadingNext && !loadFailed ? (
        <Button onPress={loadMore}>Load more activity</Button>
      ) : null}
    </section>
  );
}

function ActivityRows({ activity, empty = false }: { activity: Activity; empty?: boolean }) {
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

function BadgeText({ value }: { value: string }) {
  return <span className="runs-activity-state">{formatLabel(value)}</span>;
}
