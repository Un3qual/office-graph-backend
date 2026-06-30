import { StatusBadge } from "../components/StatusBadge";
import type { OperatorInbox, OperatorWorkflowItem } from "./api";
import type { Loadable } from "./loadable";
import { shortId } from "./presentation";
import { actionLabel } from "./status";

type Props = {
  inbox: Loadable<OperatorInbox>;
  onSelect: (id: string) => void;
  rows: OperatorWorkflowItem[];
  selectedId: string | null;
};

export function InboxPanel({ inbox, onSelect, rows, selectedId }: Props) {
  const countLabel = inbox.state === "loaded" ? `${inbox.data.rows.length} items` : "";

  return (
    <>
      <div className="pane-header">
        <h2>Inbox</h2>
        <span>{countLabel}</span>
      </div>
      {inbox.state === "loading" ? <div className="empty-state">Loading inbox...</div> : null}
      {inbox.state === "error" ? (
        <div className="empty-state error-state">{inbox.message}</div>
      ) : null}
      {inbox.state === "loaded" && inbox.data.empty ? (
        <div className="empty-state">No operator workflow items.</div>
      ) : null}
      {rows.length > 0 ? (
        <div className="inbox-list">
          {rows.map((row) => (
            <button
              aria-current={row.normalized_event_id === selectedId ? "true" : undefined}
              className="inbox-row"
              key={row.normalized_event_id}
              onClick={() => onSelect(row.normalized_event_id)}
            >
              <span className="row-title" title={row.normalized_event_id}>
                {shortId(row.normalized_event_id)}
              </span>
              <span className="row-source">{row.source.identity}</span>
              <StatusBadge status={row.status} />
              <span className="row-meta">
                {row.blocker_reasons.length > 0
                  ? `Blockers ${row.blocker_reasons.join(", ")}`
                  : `Actions ${row.allowed_next_actions.map(actionLabel).join(", ") || "None"}`}
              </span>
              <span className="row-meta" title={row.source_watermark ?? "none"}>
                Watermark {shortId(row.source_watermark)}
              </span>
            </button>
          ))}
        </div>
      ) : null}
    </>
  );
}
