import type { UseQueryResult } from "@tanstack/react-query";
import { Badge } from "../../ui/Badge";
import { EmptyState } from "../../ui/EmptyState";
import { PanelRows } from "../../ui/Panel";
import type { OperatorWorkflowItem } from "../workflowTypes";
import { formatLabel, listText, statusTone } from "../workflowPresentation";

type Props = {
  item: OperatorWorkflowItem | null;
  itemQuery: UseQueryResult<OperatorWorkflowItem>;
};

export function ItemSummary({ item, itemQuery }: Props) {
  const isLoading = itemQuery.fetchStatus === "fetching";

  return (
    <section aria-label="Item detail" className="detail-pane">
      <div className="detail-header">
        <p className="eyebrow">Selected item</p>
        <h2>{item?.title ?? "No item selected"}</h2>
      </div>
      {!item && isLoading ? <EmptyState title="Loading item detail..." /> : null}
      {itemQuery.isError ? (
        <EmptyState title={errorMessage(itemQuery.error)} tone="error">
          The selected item detail could not be loaded.
        </EmptyState>
      ) : null}
      {!item && !isLoading && !itemQuery.isError ? (
        <EmptyState title="No item selected" />
      ) : null}
      {item ? (
        <>
          <div className="stepper" aria-label="Workflow progress">
            <span>Triage</span>
            <span>Packet</span>
            <span>Run</span>
            <span>Evidence</span>
            <span>Verified</span>
          </div>
          <dl className="detail-list">
            <div>
              <dt>Status</dt>
              <dd>
                <Badge tone={statusTone(item.status)}>{formatLabel(item.status)}</Badge>
              </dd>
            </div>
            <div>
              <dt>Identity</dt>
              <dd>
                {item.typedId.type}: {item.typedId.id}
              </dd>
            </div>
            <div>
              <dt>Source</dt>
              <dd>{item.source.identity}</dd>
            </div>
            <div>
              <dt>Replay</dt>
              <dd>{item.source.replayIdentity}</dd>
            </div>
          </dl>
          <PanelRows
            rows={[
              ["Actions", listText(item.allowedNextActions)],
              ["Blockers", listText(item.blockerReasons)],
              ["Suggestions", proposedChangeText(item)],
              ["Graph links", item.graphLinks.map((link) => link.title).join(", ") || "None"],
              ["Audit trace", traceText(item.auditTrace.operationId, item.auditTrace.resourceCount)],
              [
                "Revision trace",
                traceText(item.revisionTrace.operationId, item.revisionTrace.resourceCount)
              ]
            ]}
          />
        </>
      ) : null}
    </section>
  );
}

function proposedChangeText(item: OperatorWorkflowItem) {
  const proposed = item.proposedChangeStatus;

  return `${proposed.pending} pending, ${proposed.applied} applied, ${proposed.rejected} rejected`;
}

function traceText(operationId: string | null, resourceCount: number) {
  return operationId ? `${operationId} (${resourceCount} resources)` : `${resourceCount} resources`;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Unable to load item detail.";
}
