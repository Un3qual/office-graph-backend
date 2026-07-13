import type { ReactNode } from "react";
import { Button } from "../../../src/ui/Button";
import { InboxList, InboxListFallback } from "./components/InboxList";
import { ItemSummary } from "./components/ItemSummary";
import { OperatorLayout } from "./components/OperatorLayout";
import { ReadinessPanel } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
import { OperatorInspector } from "./OperatorInspector";
import { ManualIntakeForm } from "./components/ManualIntakeForm";
import { PacketCommandForm } from "./components/PacketCommandForm";
import type { OperatorWorkflowState } from "./workflow";

type Props = {
  canPageBackward: boolean;
  fetchKey: number;
  linkedRunId: string | null;
  onManualIntakeAuthoritativeChange: (normalizedEventId?: string) => void;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
  onSelectItem: (id: string) => void;
  onRefresh: () => void;
  workflow: OperatorWorkflowState;
};

export function OperatorWorkspace({
  canPageBackward,
  fetchKey,
  linkedRunId,
  onManualIntakeAuthoritativeChange,
  onNextPage,
  onPreviousPage,
  onSelectItem,
  onRefresh,
  workflow,
}: Props) {
  const canPageForward = workflow.inbox.hasMore && workflow.inbox.nextCursor !== null;

  return (
    <OperatorLayout
      inbox={
        <InboxList
          canPageBackward={canPageBackward}
          canPageForward={canPageForward}
          intake={
            workflow.canSubmitManualIntake ? (
              <ManualIntakeForm onAuthoritativeChange={onManualIntakeAuthoritativeChange} />
            ) : null
          }
          onNextPage={() => {
            if (workflow.inbox.nextCursor !== null) onNextPage(workflow.inbox.nextCursor);
          }}
          onPreviousPage={onPreviousPage}
          onSelect={onSelectItem}
          rows={workflow.rows}
          selectedId={workflow.selectedId}
          sourceWatermark={workflow.inbox.sourceWatermark}
        />
      }
      detail={
        <>
          <ItemSummary fetchKey={fetchKey} item={workflow.selectedItem} />
          <PacketCommandForm
            item={workflow.selectedItem}
            onRefresh={onRefresh}
            readiness={null}
            readinessInput={workflow.readinessInput}
          />
        </>
      }
      inspector={
        <OperatorInspector
          fetchKey={fetchKey}
          key={`${workflow.selectedId ?? "none"}:${linkedRunId ?? "derived"}`}
          readiness={workflow.readiness}
          readinessInput={workflow.readinessInput}
          onRefresh={onRefresh}
          runId={linkedRunId ?? workflow.runId}
          selectedId={workflow.selectedId}
        />
      }
    />
  );
}

export function OperatorWorkspaceLoading() {
  return <OperatorFallbackWorkspace inbox={<InboxListFallback state="loading" />} />;
}

export function OperatorWorkspaceError({
  canPageBackward,
  onRetry,
  onPreviousPage,
}: {
  canPageBackward: boolean;
  onRetry: () => void;
  onPreviousPage: () => void;
}) {
  return (
    <OperatorFallbackWorkspace
      inbox={
        <>
          <InboxListFallback
            canPageBackward={canPageBackward}
            onPreviousPage={onPreviousPage}
            state="error"
          />
          <Button onPress={onRetry}>Retry operator workflow</Button>
        </>
      }
    />
  );
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
