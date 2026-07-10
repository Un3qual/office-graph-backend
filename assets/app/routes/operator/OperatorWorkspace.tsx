import type { ReactNode } from "react";
import { InboxList, InboxListFallback } from "./components/InboxList";
import { ItemSummary } from "./components/ItemSummary";
import { OperatorLayout } from "./components/OperatorLayout";
import { ReadinessPanel } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
import { OperatorInspector } from "./OperatorInspector";
import type { OperatorWorkflowState } from "./workflow";

type Props = {
  canPageBackward: boolean;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
  onSelectItem: (id: string) => void;
  workflow: OperatorWorkflowState;
};

export function OperatorWorkspace({
  canPageBackward,
  onNextPage,
  onPreviousPage,
  onSelectItem,
  workflow
}: Props) {
  const canPageForward = workflow.inbox.hasMore && workflow.inbox.nextCursor !== null;

  return (
    <OperatorLayout
      inbox={
        <InboxList
          canPageBackward={canPageBackward}
          canPageForward={canPageForward}
          onNextPage={() => {
            if (workflow.inbox.nextCursor !== null) {
              onNextPage(workflow.inbox.nextCursor);
            }
          }}
          onPreviousPage={onPreviousPage}
          onSelect={onSelectItem}
          rows={workflow.rows}
          selectedId={workflow.selectedId}
          sourceWatermark={workflow.inbox.sourceWatermark}
        />
      }
      detail={<ItemSummary item={workflow.selectedItem} />}
      inspector={
        <OperatorInspector
          key={workflow.selectedId ?? "none"}
          readiness={workflow.readiness}
          readinessInput={workflow.readinessInput}
          runId={workflow.runId}
          selectedId={workflow.selectedId}
        />
      }
    />
  );
}

export function OperatorWorkspaceLoading() {
  return <OperatorFallbackWorkspace inbox={<InboxListFallback state="loading" />} />;
}

export function OperatorWorkspaceError() {
  return <OperatorFallbackWorkspace inbox={<InboxListFallback state="error" />} />;
}

function OperatorFallbackWorkspace({ inbox }: { inbox: ReactNode }) {
  return (
    <OperatorLayout
      detail={<ItemSummary item={null} />}
      inbox={inbox}
      inspector={
        <>
          <ReadinessPanel readiness={null} readinessInput={null} />
          <RunPanel runId={null} runState={null} state="empty" />
          <VerificationPanel state="empty" verification={null} />
        </>
      }
    />
  );
}
