import type { UseQueryResult } from "@tanstack/react-query";
import { Badge } from "../../ui/Badge";
import { Panel, PanelRows } from "../../ui/Panel";
import type { PacketReadiness } from "../workflowTypes";
import { formatLabel, listText, statusTone } from "../workflowPresentation";

type Props = {
  readiness: PacketReadiness | null;
  readinessQuery: UseQueryResult<PacketReadiness>;
};

export function ReadinessPanel({ readiness, readinessQuery }: Props) {
  return (
    <Panel ariaLabel="Packet Readiness">
      <h2>Packet Readiness</h2>
      {readinessQuery.isPending && !readiness ? <p>Loading readiness...</p> : null}
      {readinessQuery.isError ? <p className="error-text">{errorMessage(readinessQuery.error)}</p> : null}
      {!readiness && !readinessQuery.isPending && !readinessQuery.isError ? (
        <p>No packet readiness selected.</p>
      ) : null}
      {readiness ? (
        <>
          <Badge tone={statusTone(readiness.status)}>{formatLabel(readiness.status)}</Badge>
          <PanelRows
            rows={[
              ["Mode", readiness.isDerived ? "Prepare packet context" : "Backend readiness"],
              ["Ready", readiness.ready ? "Yes" : "No"],
              ["Actions", listText(readiness.allowedNextActions)],
              ["Blockers", listText(readiness.blockerReasons)],
              ["Sources", readiness.sourceLinks.map((link) => link.title).join(", ") || "None"],
              [
                "Required checks",
                readiness.requiredChecks.map((check) => formatLabel(check.state)).join(", ") || "None"
              ]
            ]}
          />
        </>
      ) : null}
    </Panel>
  );
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Unable to load packet readiness.";
}
