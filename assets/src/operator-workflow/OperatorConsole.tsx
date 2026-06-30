import { useMemo } from "react";
import type { OperatorWorkflowApi } from "./api";
import { InboxPanel } from "./InboxPanel";
import { ItemDetailPanel } from "./ItemDetailPanel";
import {
  createDefaultOperatorWorkflowProjectionClient,
  createJsonOperatorWorkflowProjectionClient,
  type OperatorWorkflowProjectionClient
} from "./projectionClient";
import { ReadinessPanel } from "./ReadinessPanel";
import { RunStatePanel } from "./RunStatePanel";
import { useOperatorWorkflow } from "./useOperatorWorkflow";
import { VerificationPanel } from "./VerificationPanel";
import { WorkbenchLayout } from "./WorkbenchLayout";

type Props = {
  api?: OperatorWorkflowApi;
  client?: OperatorWorkflowProjectionClient;
};

const defaultClient = createDefaultOperatorWorkflowProjectionClient();

export function OperatorConsole({ api, client }: Props) {
  const resolvedClient = useMemo(
    () => client ?? (api ? createJsonOperatorWorkflowProjectionClient(api) : defaultClient),
    [api, client]
  );
  const workflow = useOperatorWorkflow(resolvedClient);

  return (
    <WorkbenchLayout
      inbox={
        <InboxPanel
          inbox={workflow.inbox}
          rows={workflow.rows}
          selectedId={workflow.selectedId}
          onSelect={workflow.selectItem}
        />
      }
      detail={<ItemDetailPanel item={workflow.item} selectedItem={workflow.selectedItem} />}
      inspector={
        <>
          <ReadinessPanel readiness={workflow.readiness} />
          <RunStatePanel runState={workflow.runState} />
          <VerificationPanel verification={workflow.verification} />
        </>
      }
    />
  );
}
