import { InboxList } from "./components/InboxList";
import { ItemSummary } from "./components/ItemSummary";
import { OperatorLayout } from "./components/OperatorLayout";
import { ReadinessPanel } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
import type { OperatorWorkflowState } from "./useOperatorWorkflow";

type Props = {
  workflow: OperatorWorkflowState;
};

export function OperatorWorkspace({ workflow }: Props) {
  return (
    <OperatorLayout
      inbox={
        <InboxList
          inbox={workflow.inboxQuery}
          rows={workflow.rows}
          selectedId={workflow.selectedId}
          onSelect={workflow.selectItem}
        />
      }
      detail={<ItemSummary item={workflow.selectedItem} itemQuery={workflow.itemQuery} />}
      inspector={
        <>
          <ReadinessPanel
            readiness={workflow.readiness}
            readinessQuery={workflow.readinessQuery}
          />
          <RunPanel runId={workflow.runId} runState={workflow.runStateQuery} />
          <VerificationPanel verification={workflow.verification} />
        </>
      }
    />
  );
}
