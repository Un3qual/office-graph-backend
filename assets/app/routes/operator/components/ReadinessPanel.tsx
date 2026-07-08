import { Badge } from "../../../../src/ui/Badge";
import { Panel, PanelRows } from "../../../../src/ui/Panel";
import {
  enabledCommandIdentities,
  formatLabel,
  isQueryLoading,
  listText,
  statusTone
} from "../presentation";
import type { PacketReadiness, PacketReadinessInput, QueryState } from "../types";

type Props = {
  readiness: PacketReadiness | null;
  readinessInput: PacketReadinessInput | null;
  readinessQuery: QueryState<PacketReadiness>;
};

export function ReadinessPanel({ readiness, readinessInput, readinessQuery }: Props) {
  const isLoading = isQueryLoading(readinessQuery);
  const hasStaleData = readinessQuery.isError && Boolean(readiness);

  return (
    <Panel ariaLabel="Packet Readiness">
      <h2>Packet Readiness</h2>
      {isLoading && !readiness ? <p>Loading readiness...</p> : null}
      {readinessQuery.isError ? <p className="error-text">{errorMessage(readinessQuery.error)}</p> : null}
      {!readiness && !isLoading && !readinessQuery.isError ? (
        <p>No packet readiness selected.</p>
      ) : null}
      {readiness ? (
        <>
          {hasStaleData ? <p className="muted-text">Showing last loaded readiness.</p> : null}
          <Badge tone={statusTone(readiness.status)}>{formatLabel(readiness.status)}</Badge>
          <PanelRows
            rows={[
              ["Mode", readiness.isDerived ? "Prepare packet context" : "Backend readiness"],
              ["Ready", readiness.ready ? "Yes" : "No"],
              [
                "Actions",
                listText(
                  enabledCommandIdentities(
                    readiness.commandAffordances,
                    readiness.allowedNextActions
                  )
                )
              ],
              ["Blockers", listText(readiness.blockerReasons)],
              ["Objective", readinessInput?.objective || "None"],
              ["Context", readinessInput?.contextSummary || "None"],
              ["Success criteria", readinessInput?.successCriteria || "None"],
              ["Autonomy", formatLabel(readinessInput?.autonomyPosture)],
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
