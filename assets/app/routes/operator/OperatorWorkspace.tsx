import type { ReactNode } from "react";
import { Panel } from "../../../src/ui/Panel";
import { InboxList, InboxListFallback } from "./components/InboxList";
import { ItemSummary } from "./components/ItemSummary";
import { OperatorLayout } from "./components/OperatorLayout";
import { ReadinessPanel } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
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
        <>
          <ReadinessPanel
            onValidateReadiness={workflow.validatePacketReadiness}
            readiness={workflow.readiness}
            readinessInput={workflow.readinessInput}
            readinessQuery={workflow.readinessQuery}
          />
          <RunPanel runId={workflow.runId} runState={workflow.runStateQuery} />
          <VerificationPanel verification={workflow.verification} />
        </>
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
          <Panel ariaLabel="Packet Readiness">
            <h2>Packet Readiness</h2>
            <p>No packet readiness selected.</p>
          </Panel>
          <Panel ariaLabel="Run State">
            <h2>Run State</h2>
            <p>No run linked yet.</p>
          </Panel>
          <Panel ariaLabel="Verification">
            <h2>Verification</h2>
            <p>No verification outcome selected.</p>
          </Panel>
        </>
      }
    />
  );
}
