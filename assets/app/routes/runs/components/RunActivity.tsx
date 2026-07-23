import type { RunDetailState } from "../types";
import { formatLabel } from "./RunList";

export function RunActivity({ activity }: { activity: RunDetailState["activity"] }) {
  return (
    <section aria-label="Run activity" className="runs-activity">
      <div className="runs-section-heading">
        <h3>Recent activity</h3>
        <span>First 5 events</span>
      </div>
      {(activity?.edges ?? []).length === 0 ? (
        <p>No activity is available for this run.</p>
      ) : (
        <ol>
          {(activity?.edges ?? []).flatMap((edge) =>
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
      )}
    </section>
  );
}

function BadgeText({ value }: { value: string }) {
  return <span className="runs-activity-state">{formatLabel(value)}</span>;
}
