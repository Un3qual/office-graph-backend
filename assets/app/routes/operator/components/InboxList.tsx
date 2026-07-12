import { Badge } from "../../../../src/ui/Badge";
import type { ReactNode } from "react";
import { EmptyState } from "../../../../src/ui/EmptyState";
import { PaneHeader } from "../../../../src/ui/Panel";
import { itemTitle } from "../derived";
import { commandAffordanceListText, formatLabel, listText, statusTone } from "../presentation";
import type { OperatorWorkflowItem } from "../workflow";

type Props = {
  canPageBackward: boolean;
  canPageForward: boolean;
  intake?: ReactNode;
  onNextPage: () => void;
  onPreviousPage: () => void;
  onSelect: (id: string) => void;
  rows: OperatorWorkflowItem[];
  selectedId: string | null;
  sourceWatermark: string | null;
};

type FallbackProps = {
  canPageBackward?: boolean;
  onPreviousPage?: () => void;
  state: "error" | "loading";
};

export function InboxList({
  canPageBackward,
  canPageForward,
  intake,
  onNextPage,
  onPreviousPage,
  onSelect,
  rows,
  selectedId,
  sourceWatermark
}: Props) {
  return (
    <section aria-label="Inbox" className="inbox-pane">
      <PaneHeader title="Inbox" meta={sourceWatermark ?? "Live projection"} />
      {intake}
      {rows.length === 0 ? (
        <EmptyState title="No operator workflow items.">
          There are no manual intake or verification commands ready right now.
        </EmptyState>
      ) : (
        <div className="inbox-list">
          {rows.map((row) => {
            const commands = commandAffordanceListText(
              row.commandAffordances,
              row.allowedNextActions
            );
            const context =
              commands === "None" && row.blockerReasons.length > 0
                ? `Blockers ${listText(row.blockerReasons)}`
                : `Commands ${commands}`;

            return (
              <button
                aria-current={row.normalizedEventId === selectedId ? "true" : undefined}
                className="inbox-row"
                key={row.normalizedEventId}
                onClick={() => onSelect(row.normalizedEventId)}
              >
                <span className="row-title">{itemTitle(row)}</span>
                <Badge tone={statusTone(row.status)}>{formatLabel(row.status)}</Badge>
                <span className="row-source">{row.sourceSummary}</span>
                <span className="row-meta">
                  {context} · Watermark {row.sourceWatermark ?? "None"}
                </span>
              </button>
            );
          })}
        </div>
      )}
      <div aria-label="Inbox pagination" className="inbox-pagination">
        <span>{rows.length === 1 ? "1 row" : `${rows.length} rows`}</span>
        <button type="button" disabled={!canPageBackward} onClick={onPreviousPage}>
          Previous
        </button>
        <button type="button" disabled={!canPageForward} onClick={onNextPage}>
          Next
        </button>
      </div>
    </section>
  );
}

export function InboxListFallback({
  canPageBackward = false,
  onPreviousPage,
  state
}: FallbackProps) {
  return (
    <section aria-label="Inbox" className="inbox-pane">
      <PaneHeader title="Inbox" meta="Live projection" />
      {state === "loading" ? (
        <div role="status">
          <EmptyState title="Loading inbox..." />
        </div>
      ) : (
        <div role="alert">
          <EmptyState title="Unable to load operator inbox." tone="error">
            The operator workflow projection could not be loaded.
          </EmptyState>
        </div>
      )}
      {state === "error" ? (
        <div aria-label="Inbox pagination" className="inbox-pagination">
          <span>0 rows</span>
          <button
            type="button"
            disabled={!canPageBackward}
            onClick={onPreviousPage}
          >
            Previous
          </button>
          <button type="button" disabled>
            Next
          </button>
        </div>
      ) : null}
    </section>
  );
}
