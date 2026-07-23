import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { RunDetail } from "./components/RunDetail";
import { RunList } from "./components/RunList";
import { RunsLayout } from "./components/RunsLayout";
import type { RunSummary } from "./types";
import { useRunDetail } from "./workflow";

type Props = {
  canPageBackward: boolean;
  detailFetchKey: number;
  hasNextPage: boolean;
  isSelectionPending: boolean;
  loadNextPage: () => void;
  loadPreviousPage: () => void;
  onDetailRetry: () => void;
  onSelectRun: (id: string) => void;
  rows: RunSummary[];
  selectedId: string | null;
};

export function RunWorkspace({
  canPageBackward,
  detailFetchKey,
  hasNextPage,
  isSelectionPending,
  loadNextPage,
  loadPreviousPage,
  onDetailRetry,
  onSelectRun,
  rows,
  selectedId,
}: Props) {
  return (
    <RunsLayout
      detail={
        selectedId === null ? (
          <RunDetail selectedId={null} state="empty" />
        ) : isSelectionPending ? (
          <RunDetail selectedId={selectedId} state="loading" />
        ) : (
          <AsyncBoundary
            errorFallback={
              <RunDetail onRetry={onDetailRetry} selectedId={selectedId} state="error" />
            }
            loadingFallback={<RunDetail selectedId={selectedId} state="loading" />}
            resetKey={`run-detail:${selectedId}:${detailFetchKey}`}
          >
            <LoadedRunDetail
              fetchKey={detailFetchKey}
              key={selectedId}
              onRetry={onDetailRetry}
              runId={selectedId}
            />
          </AsyncBoundary>
        )
      }
      list={
        <RunList
          canPageBackward={canPageBackward}
          hasNextPage={hasNextPage}
          onNextPage={loadNextPage}
          onPreviousPage={loadPreviousPage}
          onSelect={onSelectRun}
          rows={rows}
          selectedId={selectedId}
        />
      }
    />
  );
}

function LoadedRunDetail({
  fetchKey,
  onRetry,
  runId,
}: {
  fetchKey: number;
  onRetry: () => void;
  runId: string;
}) {
  const detail = useRunDetail(runId, fetchKey);

  return <RunDetail detail={detail} onRetry={onRetry} selectedId={runId} state="loaded" />;
}
