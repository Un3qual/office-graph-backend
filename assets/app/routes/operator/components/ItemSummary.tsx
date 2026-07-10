import { Badge } from "../../../../src/ui/Badge";
import { EmptyState } from "../../../../src/ui/EmptyState";
import { PanelRows } from "../../../../src/ui/Panel";
import { itemTitle } from "../derived";
import {
  commandAffordanceListText,
  formatLabel,
  listText,
  statusTone
} from "../presentation";
import type { OperatorWorkflowItem } from "../workflow";

type Props = {
  item: OperatorWorkflowItem | null;
};

export function ItemSummary({ item }: Props) {
  return (
    <section aria-label="Item detail" className="detail-pane">
      <div className="detail-header">
        <p className="eyebrow">Selected item</p>
        <h2>{item ? itemTitle(item) : "No item selected"}</h2>
      </div>
      {!item ? <EmptyState title="No item selected" /> : null}
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
              [
                "Commands",
                commandAffordanceListText(item.commandAffordances, item.allowedNextActions)
              ],
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

function traceText(operationId: string | null | undefined, resourceCount: number) {
  return operationId ? `${operationId} (${resourceCount} resources)` : `${resourceCount} resources`;
}
