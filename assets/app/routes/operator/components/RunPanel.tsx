import { Badge } from "../../../../src/ui/Badge";
import { Panel, PanelRows } from "../../../../src/ui/Panel";
import {
  commandAffordanceListText,
  formatLabel,
  isQueryLoading,
  listText,
  statusTone
} from "../presentation";
import type { OperatorRunState, QueryState } from "../types";

type Props = {
  runId: string | null;
  runState: QueryState<OperatorRunState>;
};

export function RunPanel({ runId, runState }: Props) {
  const isLoading = isQueryLoading(runState);
  const hasStaleData = runState.isError && Boolean(runState.data);

  return (
    <Panel ariaLabel="Run State">
      <h2>Run State</h2>
      {!runId ? <p>No run linked yet.</p> : null}
      {runId && isLoading && !runState.data ? <p>Loading run state...</p> : null}
      {runState.isError ? <p className="error-text">{errorMessage(runState.error)}</p> : null}
      {runState.data ? (
        <>
          {hasStaleData ? <p className="muted-text">Showing last loaded run state.</p> : null}
          <Badge tone={statusTone(runState.data.status)}>{formatLabel(runState.data.status)}</Badge>
          <PanelRows
            rows={[
              ["Packet", runState.data.packet.title],
              ["Objective", runState.data.packetVersion.objective ?? "None"],
              [
                "Commands",
                commandAffordanceListText(
                  runState.data.commandAffordances,
                  runState.data.allowedNextActions
                )
              ],
              ["Execution", formatLabel(runState.data.run.executionState)],
              ["Verification", formatLabel(runState.data.run.verificationState)],
              [
                "Required checks",
                runState.data.requiredChecks
                  .map(
                    (check) =>
                      `${check.verificationCheckId ?? "unknown"}: ${formatLabel(check.state)}`
                  )
                  .join(", ") || "None"
              ],
              [
                "Suggested evidence",
                runState.data.evidenceCandidates.map((candidate) => candidate.claim).join(", ") ||
                  "None"
              ],
              [
                "Observations",
                runState.data.observations
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

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Unable to load run state.";
}
