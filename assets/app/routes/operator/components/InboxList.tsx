import { Badge } from "../../../../src/ui/Badge";
import { EmptyState } from "../../../../src/ui/EmptyState";
import { PaneHeader } from "../../../../src/ui/Panel";
import { itemTitle } from "../derived";
import { commandAffordanceListText, formatLabel, listText, statusTone } from "../presentation";
import type { OperatorWorkflowState } from "../workflow";

type Props = {
  canPageBackward: OperatorWorkflowState["canPageBackward"];
  inbox: OperatorWorkflowState["inboxQuery"];
  onNextPage: OperatorWorkflowState["loadNextInboxPage"];
  onPreviousPage: OperatorWorkflowState["loadPreviousInboxPage"];
  rows: OperatorWorkflowState["rows"];
  selectedId: OperatorWorkflowState["selectedId"];
  onSelect: OperatorWorkflowState["selectInboxItem"];
};

export function InboxList({
  canPageBackward,
  inbox,
  onNextPage,
  onPreviousPage,
  onSelect,
  rows,
  selectedId
}: Props) {
  const hasStaleData = inbox.isError && rows.length > 0;
  const canPageForward = Boolean(inbox.data?.hasMore && inbox.data.nextCursor !== null);

  return (
    <section aria-label="Inbox" className="inbox-pane">
      <PaneHeader title="Inbox" meta={inbox.data?.sourceWatermark ?? "Live projection"} />
      {inbox.isPending ? <EmptyState title="Loading inbox..." /> : null}
      {inbox.isError ? (
        <EmptyState title={errorMessage(inbox.error)} tone="error">
          The operator workflow projection could not be loaded.
        </EmptyState>
      ) : null}
      {hasStaleData ? <p className="muted-text">Showing last loaded inbox.</p> : null}
      {inbox.isSuccess && rows.length === 0 ? (
        <EmptyState title="No operator workflow items.">
          There are no manual intake or verification commands ready right now.
        </EmptyState>
      ) : null}
      {rows.length > 0 ? (
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
                <span className="row-source">{row.source.identity}</span>
                <span className="row-meta">
                  {context} · Watermark {row.sourceWatermark ?? "None"}
                </span>
              </button>
            );
          })}
        </div>
      ) : null}
      {inbox.data ? (
        <div aria-label="Inbox pagination" className="inbox-pagination">
          <span>{rows.length === 1 ? "1 row" : `${rows.length} rows`}</span>
          <button type="button" disabled={!canPageBackward} onClick={onPreviousPage}>
            Previous
          </button>
          <button type="button" disabled={!canPageForward} onClick={onNextPage}>
            Next
          </button>
        </div>
      ) : null}
    </section>
  );
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Unable to load operator inbox.";
}
