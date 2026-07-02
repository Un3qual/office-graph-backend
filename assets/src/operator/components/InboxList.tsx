import type { UseQueryResult } from "@tanstack/react-query";
import { Badge } from "../../ui/Badge";
import { EmptyState } from "../../ui/EmptyState";
import { PaneHeader } from "../../ui/Panel";
import type { OperatorInbox, OperatorWorkflowItem } from "../workflowTypes";
import { formatLabel, listText, statusTone } from "../workflowPresentation";

type Props = {
  inbox: UseQueryResult<OperatorInbox>;
  rows: OperatorWorkflowItem[];
  selectedId: string | null;
  onSelect: (id: string) => void;
};

export function InboxList({ inbox, onSelect, rows, selectedId }: Props) {
  return (
    <section aria-label="Inbox" className="inbox-pane">
      <PaneHeader title="Inbox" meta={inbox.data?.sourceWatermark ?? "Live projection"} />
      {inbox.isPending ? <EmptyState title="Loading inbox..." /> : null}
      {inbox.isError ? (
        <EmptyState title={errorMessage(inbox.error)} tone="error">
          The operator workflow projection could not be loaded.
        </EmptyState>
      ) : null}
      {inbox.isSuccess && rows.length === 0 ? (
        <EmptyState title="No operator workflow items.">
          There are no actionable manual intake or verification items right now.
        </EmptyState>
      ) : null}
      {rows.length > 0 ? (
        <div className="inbox-list">
          {rows.map((row) => {
            const context =
              row.blockerReasons.length > 0
                ? `Blockers ${listText(row.blockerReasons)}`
                : `Actions ${listText(row.allowedNextActions)}`;

            return (
              <button
                aria-current={row.normalizedEventId === selectedId ? "true" : undefined}
                className="inbox-row"
                key={row.normalizedEventId}
                onClick={() => onSelect(row.normalizedEventId)}
              >
                <span className="row-title">{row.title}</span>
                <Badge tone={statusTone(row.status)}>{formatLabel(row.status)}</Badge>
                <span className="row-source">{row.source.identity}</span>
                <span className="row-meta">
                  {context} · Watermark {row.sourceWatermark ?? "None"}
                </span>
              </button>
            );
          })}
        </div>
      ) : null}
    </section>
  );
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Unable to load operator inbox.";
}
