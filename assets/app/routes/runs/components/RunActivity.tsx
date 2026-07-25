import { useCallback, useEffect, useRef, useState } from "react";
import { usePaginationFragment } from "react-relay";
import { Button } from "../../../../src/ui/Button";
import type {
  RunActivityFragment$data,
  RunActivityFragment$key,
} from "../../../relay/__generated__/RunActivityFragment.graphql";
import { RunActivityFragment } from "../data";
import { runActivityPageSize } from "../workflow";
import { formatLabel } from "./RunList";

type ActivityResult = RunActivityFragment$data["operatorRunState"]["activity"];
type Activity = Extract<ActivityResult, { readonly ok: true }>["value"];

export function RunActivity({ activityRef }: { activityRef: RunActivityFragment$key }) {
  const { data, hasNext, isLoadingNext, loadNext } = usePaginationFragment(
    RunActivityFragment,
    activityRef,
  );
  const [loadFailed, setLoadFailed] = useState(false);
  const activityResult = data.operatorRunState.activity;
  const lastSuccessfulPage = useRef<{
    activity: Activity;
    hasNext: boolean;
    loadNext: typeof loadNext;
  } | null>(null);

  useEffect(() => {
    if (activityResult.ok) {
      lastSuccessfulPage.current = {
        activity: activityResult.value,
        hasNext,
        loadNext,
      };
    }
  }, [activityResult, hasNext, loadNext]);

  const fieldLoadFailed = !activityResult.ok;
  const retainedPage = lastSuccessfulPage.current;
  const activity = activityResult.ok ? activityResult.value : retainedPage?.activity;
  const pageLoadFailed = loadFailed || fieldLoadFailed;
  const loadMore = useCallback(() => {
    const canLoad = fieldLoadFailed ? retainedPage?.hasNext : hasNext;
    const load = fieldLoadFailed ? retainedPage?.loadNext : loadNext;

    if (!canLoad || !load || isLoadingNext) {
      return;
    }

    setLoadFailed(false);
    load(runActivityPageSize, {
      onComplete: (error) => setLoadFailed(error !== null),
    });
  }, [fieldLoadFailed, hasNext, isLoadingNext, loadNext, retainedPage]);

  if (fieldLoadFailed && retainedPage === null) {
    throw new Error("Run activity is unavailable.");
  }

  return (
    <section aria-label="Run activity" className="runs-activity">
      <div className="runs-section-heading">
        <h3>Recent activity</h3>
        <span>{runActivityPageSize} events per page</span>
      </div>
      <ActivityRows activity={activity} empty />
      {isLoadingNext ? <p role="status">Loading more activity...</p> : null}
      {pageLoadFailed ? (
        <div role="alert">
          <p>Unable to load more activity.</p>
          <Button onPress={loadMore}>Retry activity</Button>
        </div>
      ) : null}
      {hasNext && !isLoadingNext && !pageLoadFailed ? (
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
