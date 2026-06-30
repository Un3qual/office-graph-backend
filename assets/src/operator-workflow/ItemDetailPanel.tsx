import { StatusBadge } from "../components/StatusBadge";
import type { OperatorWorkflowItem } from "./api";
import type { Loadable } from "./loadable";
import { listSummary } from "./presentation";
import { actionLabel, formatWorkflowStatus } from "./status";

type Props = {
  item: Loadable<OperatorWorkflowItem>;
  selectedItem: OperatorWorkflowItem | null;
};

export function ItemDetailPanel({ item, selectedItem }: Props) {
  if (item.state === "loading") {
    return <div className="empty-state">Loading item detail...</div>;
  }

  if (item.state === "error") {
    return <div className="empty-state error-state">{item.message}</div>;
  }

  if (!selectedItem) {
    return (
      <div className="detail-header">
        <p className="eyebrow">Selected item</p>
        <h2>No item selected</h2>
      </div>
    );
  }

  return (
    <>
      <div className="detail-header">
        <p className="eyebrow">Selected item</p>
        <h2>{selectedItem.normalized_event_id}</h2>
        <StatusBadge status={selectedItem.status} />
      </div>
      <div className="stepper" aria-label="Workflow steps">
        {["Manual Intake", "Packet Readiness", "Run State", "Evidence", "Verification"].map(
          (step) => (
            <span key={step}>{step}</span>
          )
        )}
      </div>
      <dl className="detail-list">
        <div>
          <dt>Typed identity</dt>
          <dd>
            {selectedItem.typed_id.type}: {selectedItem.typed_id.id}
          </dd>
        </div>
        <div>
          <dt>Source</dt>
          <dd>{selectedItem.source.identity}</dd>
        </div>
        <div>
          <dt>Outcome</dt>
          <dd>{formatWorkflowStatus(selectedItem.source.outcome)}</dd>
        </div>
        <div>
          <dt>Allowed next actions</dt>
          <dd>{selectedItem.allowed_next_actions.map(actionLabel).join(", ") || "None"}</dd>
        </div>
        <div>
          <dt>Proposed changes</dt>
          <dd>
            {selectedItem.proposed_change_status.applied} applied /{" "}
            {selectedItem.proposed_change_status.pending} pending
          </dd>
        </div>
        <div>
          <dt>Graph links</dt>
          <dd title={selectedItem.graph_links.map((link) => link.title).join(", ")}>
            {listSummary(
              selectedItem.graph_links.map((link) => link.title),
              2
            )}
          </dd>
        </div>
        <div>
          <dt>Audit trace</dt>
          <dd>{selectedItem.audit_trace.resource_count} resources</dd>
        </div>
        <div>
          <dt>Revision trace</dt>
          <dd>{selectedItem.revision_trace.resource_count} resources</dd>
        </div>
      </dl>
    </>
  );
}
