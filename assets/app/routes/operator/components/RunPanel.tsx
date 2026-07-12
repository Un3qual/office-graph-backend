import { Badge } from "../../../../src/ui/Badge";
import { Panel, PanelRows } from "../../../../src/ui/Panel";
import {
  commandAffordanceListText,
  formatLabel,
  statusTone
} from "../presentation";
import type { OperatorRunState } from "../workflow";

type Props = {
  runId: string | null;
  runState: OperatorRunState | null;
  state: "empty" | "error" | "loaded" | "loading";
};

export function RunPanel({ runId, runState, state }: Props) {
  return (
    <Panel ariaLabel="Run State">
      <h2>Run State</h2>
      {state === "empty" || !runId ? <p>No run linked yet.</p> : null}
      {state === "loading" ? <p>Loading run state...</p> : null}
      {state === "error" ? <p className="error-text">Run state unavailable.</p> : null}
      {state === "loaded" && runState ? (
        <>
          <Badge tone={statusTone(runState.status)}>{formatLabel(runState.status)}</Badge>
          <PanelRows
            rows={[
              ["Packet", runState.packet.title],
              ["Objective", runState.packetVersion.objective ?? "None"],
              [
                "Commands",
                commandAffordanceListText(
                  runState.commandAffordances,
                  runState.allowedNextActions
                )
              ],
              ["Execution", formatLabel(runState.run.executionState)],
              ["Verification", formatLabel(runState.run.verificationState)],
              [
                "Run activity",
                `${runState.childSummary.requiredChecks} checks · ${runState.childSummary.observations} observations · ${runState.childSummary.evidenceCandidates} evidence suggestions${runState.childSummary.hasMore ? " · more available" : ""}`
              ],
              [
                "Required checks",
                runState.requiredChecks
                  .map(
                    (check) =>
                      `${check.verificationCheckId ?? "unknown"}: ${formatLabel(check.state)}`
                  )
                  .join(", ") || "None"
              ],
              [
                "Suggested evidence",
                runState.evidenceCandidates.map((candidate) => candidate.claim).join(", ") ||
                  "None"
              ],
              [
                "Observations",
                runState.observations
                  .map(
                    (observation) =>
                      `${formatLabel(observation.normalizedStatus)} · ${formatLabel(
                        observation.freshnessState
                      )} · ${formatLabel(observation.trustBasis)} · ${observation.sourceIdentity}`
                  )
                  .join(", ") || "None"
              ]
            ]}
          />
        </>
      ) : null}
    </Panel>
  );
}
