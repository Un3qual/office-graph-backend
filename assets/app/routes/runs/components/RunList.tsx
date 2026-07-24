import { Badge } from "../../../../src/ui/Badge";
import { Button } from "../../../../src/ui/Button";
import { EmptyState } from "../../../../src/ui/EmptyState";
import type { ReactNode } from "react";
import type { RunSummary } from "../types";

type Props = {
  canPageBackward: boolean;
  hasNextPage: boolean;
  isPaging: boolean;
  onNextPage: () => void;
  onPreviousPage: () => void;
  onSelect: (id: string) => void;
  pageAttempt: ReactNode;
  rows: RunSummary[];
  selectedId: string | null;
};

export function RunList({
  canPageBackward,
  hasNextPage,
  isPaging,
  onNextPage,
  onPreviousPage,
  onSelect,
  pageAttempt,
  rows,
  selectedId,
}: Props) {
  return (
    <RunListFrame
      footer={
        <>
          {pageAttempt}
          <Button isDisabled={isPaging || !canPageBackward} onPress={onPreviousPage}>
            Previous
          </Button>
          <Button isDisabled={isPaging || !hasNextPage} onPress={onNextPage}>
            Next
          </Button>
        </>
      }
      rowCount={rows.length}
    >
      {rows.length === 0 ? (
        <EmptyState title="No runs are available.">
          Authorized work runs will appear here as work begins.
        </EmptyState>
      ) : (
        <div className="runs-list">
          {rows.map((run) => (
            <button
              aria-current={run.id === selectedId ? "true" : undefined}
              className="runs-row"
              key={run.id}
              onClick={() => onSelect(run.id)}
              type="button"
            >
              <span className="runs-row-heading">
                <span className="runs-row-title">{run.objective ?? `Run ${run.id}`}</span>
                <span className="runs-row-time">{formatRunTimestamp(run.insertedAt)}</span>
              </span>
              <span className="runs-row-states">
                <Badge>{formatLabel(run.aggregateState)}</Badge>
                <Badge>{formatLabel(run.executionState)}</Badge>
                <Badge>{formatLabel(run.verificationState)}</Badge>
              </span>
              <span className="runs-row-packet">{run.packet.title}</span>
            </button>
          ))}
        </div>
      )}
    </RunListFrame>
  );
}

export function RunPageStatus({
  direction,
  onRetry,
  state,
}: {
  direction: "next" | "previous";
  onRetry?: () => void;
  state: "error" | "loading";
}) {
  if (state === "loading") {
    return (
      <div className="runs-page-status" role="status">
        Loading {direction} run page...
      </div>
    );
  }

  return (
    <div className="runs-page-status" role="alert">
      Unable to load {direction} run page.
      {onRetry ? <Button onPress={onRetry}>Retry run page</Button> : null}
    </div>
  );
}

export function RunListFallback({
  canPageBackward = false,
  onPreviousPage,
  onRetry,
  state,
}: {
  canPageBackward?: boolean;
  onPreviousPage?: () => void;
  onRetry?: () => void;
  state: "error" | "initial-loading";
}) {
  return (
    <RunListFrame
      footer={
        <>
          <Button isDisabled={!canPageBackward} onPress={onPreviousPage}>
            Previous
          </Button>
          <Button isDisabled>Next</Button>
        </>
      }
      rowCount={0}
    >
      {state === "error" ? (
        <div role="alert">
          <EmptyState title="Unable to load runs." tone="error">
            Retry the authorized run list.
          </EmptyState>
          {onRetry ? <Button onPress={onRetry}>Retry runs</Button> : null}
        </div>
      ) : (
        <p className="runs-loading" role="status">
          Loading runs...
        </p>
      )}
    </RunListFrame>
  );
}

export function formatLabel(value: string | null | undefined) {
  if (!value) {
    return "None";
  }

  const label = value.split("_").filter(Boolean).join(" ");
  return label.slice(0, 1).toUpperCase() + label.slice(1);
}

function RunListFrame({
  children,
  footer,
  rowCount,
}: {
  children: React.ReactNode;
  footer: React.ReactNode;
  rowCount: number;
}) {
  return (
    <section aria-label="Run list" className="runs-list-pane">
      <header className="runs-pane-header">
        <div>
          <p className="eyebrow">Authorized workspace</p>
          <h2>Work runs</h2>
        </div>
        <span>{rowCount} rows</span>
      </header>
      <div className="runs-list-content">{children}</div>
      <footer aria-label="Run pagination" className="runs-pagination">
        <span>{rowCount} rows</span>
        {footer}
      </footer>
    </section>
  );
}

function formatRunTimestamp(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? value : date.toLocaleString();
}
