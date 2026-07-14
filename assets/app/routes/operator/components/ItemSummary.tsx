import { useState } from "react";
import { useLazyLoadQuery } from "react-relay";
import { Badge } from "../../../../src/ui/Badge";
import { Button } from "../../../../src/ui/Button";
import { EmptyState } from "../../../../src/ui/EmptyState";
import { PanelRows } from "../../../../src/ui/Panel";
import { itemTitle } from "../derived";
import { commandAffordanceListText, formatLabel, listText, statusTone } from "../presentation";
import type { OperatorWorkflowItem } from "../workflow";
import { OperatorRelationshipDetailsQuery } from "../data";
import type { OperatorRelationshipDetailsQuery as OperatorRelationshipDetailsOperation } from "../../../relay/__generated__/OperatorRelationshipDetailsQuery.graphql";

type Props = {
  fetchKey?: number;
  item: OperatorWorkflowItem | null;
};

export function ItemSummary({ fetchKey, item }: Props) {
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
              <dd>{item.sourceSummary}</dd>
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
                commandAffordanceListText(item.commandAffordances, item.allowedNextActions),
              ],
              ["Blockers", listText(item.blockerReasons)],
              ["Suggestions", proposedChangeText(item)],
              ["Graph links", graphLinkSummary(item)],
              [
                "Audit trace",
                traceText(item.auditTrace.operationId, item.auditTrace.resourceCount),
              ],
              [
                "Revision trace",
                traceText(item.revisionTrace.operationId, item.revisionTrace.resourceCount),
              ],
            ]}
          />
          {item.relationshipSummary.hasMore ? (
            <RelationshipOverflowDetails
              fetchKey={fetchKey}
              key={`${item.normalizedEventId}:${fetchKey ?? "initial"}`}
              normalizedEventId={item.normalizedEventId}
            />
          ) : null}
        </>
      ) : null}
    </section>
  );
}

function RelationshipOverflowDetails({
  fetchKey,
  normalizedEventId,
}: {
  fetchKey?: number;
  normalizedEventId: string;
}) {
  const [cursors, setCursors] = useState<Array<string | null>>([null]);
  const after = cursors.at(-1) ?? null;
  const data = useLazyLoadQuery<OperatorRelationshipDetailsOperation>(
    OperatorRelationshipDetailsQuery,
    { id: normalizedEventId, first: 5, after },
    { fetchKey, fetchPolicy: "network-only" },
  );
  const connection = data.operatorRelationshipDetails;

  return (
    <section aria-label="Relationship detail">
      <h3>Related graph detail</h3>
      <ul>
        {(connection?.edges ?? []).flatMap((edge) =>
          edge?.node
            ? [
                <li key={`${edge.node.kind}:${edge.node.stableId}`}>
                  {edge.node.title}
                  {" · "}
                  {formatLabel(edge.node.definitionKey ?? edge.node.linkType ?? edge.node.kind)}
                </li>,
              ]
            : [],
        )}
      </ul>
      <div aria-label="Relationship pagination">
        {connection?.pageInfo.hasPreviousPage ? (
          <Button
            onPress={() =>
              setCursors((current) => (current.length > 1 ? current.slice(0, -1) : current))
            }
          >
            Previous relationship page
          </Button>
        ) : null}
        {connection?.pageInfo.hasNextPage ? (
          <Button
            onPress={() => {
              const cursor = connection.pageInfo.endCursor;
              if (cursor) setCursors((current) => [...current, cursor]);
            }}
          >
            Next relationship page
          </Button>
        ) : null}
      </div>
    </section>
  );
}

function graphLinkSummary(item: OperatorWorkflowItem) {
  const labels = item.graphLinks.map((link) => link.title).join(", ") || "None";
  const summary = item.relationshipSummary;
  const counts = `${summary.graphLinks} links, ${summary.graphRelationships} relationships`;
  return summary.hasMore ? `${labels} (${counts}; more available)` : `${labels} (${counts})`;
}

function proposedChangeText(item: OperatorWorkflowItem) {
  if (item.proposedActionPreviews.length > 0) {
    return item.proposedActionPreviews
      .map((preview) => `${formatLabel(preview.action)}: ${preview.title}`)
      .join(", ");
  }

  const proposed = item.proposedChangeStatus;
  return `${proposed.pending} pending, ${proposed.applied} applied, ${proposed.rejected} rejected`;
}

function traceText(operationId: string | null | undefined, resourceCount: number) {
  return operationId ? `${operationId} (${resourceCount} resources)` : `${resourceCount} resources`;
}
