import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { RunDetail } from "./components/RunDetail";
import { RunsLayout } from "./components/RunsLayout";
import { useRunDetail } from "./workflow";

type Props = {
  detailFetchKey: number;
  isSelectionPending: boolean;
  list: React.ReactNode;
  onDetailRetry: () => void;
  selectedId: string | null;
};

export function RunWorkspace({
  detailFetchKey,
  isSelectionPending,
  list,
  onDetailRetry,
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
      list={list}
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
