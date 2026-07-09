import { InboxList } from "./components/InboxList";
import { ItemSummary } from "./components/ItemSummary";
import { OperatorLayout } from "./components/OperatorLayout";
import { ReadinessPanel } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
import type { OperatorWorkflowState } from "./workflow";

type Props = {
  workflow: OperatorWorkflowState;
};

export function OperatorWorkspace({ workflow }: Props) {
  return (
    <OperatorLayout
      inbox={
        <InboxList
          canPageBackward={workflow.canPageBackward}
          inbox={workflow.inboxQuery}
          onNextPage={workflow.loadNextInboxPage}
          onPreviousPage={workflow.loadPreviousInboxPage}
          rows={workflow.rows}
          selectedId={workflow.selectedId}
          onSelect={workflow.selectInboxItem}
        />
      }
      detail={<ItemSummary item={workflow.selectedItem} itemQuery={workflow.itemQuery} />}
      inspector={
        <>
          <ReadinessPanel
            commandExecution={workflow.commandExecution}
            onExecutePacketRun={workflow.executePacketRunVerification}
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
