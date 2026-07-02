import type { UseQueryResult } from "@tanstack/react-query";
import { Badge } from "../../ui/Badge";
import { Panel, PanelRows } from "../../ui/Panel";
import type { OperatorRunState } from "../workflowTypes";
import { formatLabel, listText, statusTone } from "../workflowPresentation";

type Props = {
  runId: string | null;
  runState: UseQueryResult<OperatorRunState>;
};

export function RunPanel({ runId, runState }: Props) {
  const isLoading = runState.fetchStatus === "fetching";
  const hasStaleData = runState.isError && Boolean(runState.data);

  return (
    <Panel ariaLabel="Run State">
      <h2>Run State</h2>
      {!runId ? <p>No run linked yet.</p> : null}
      {runId && isLoading ? <p>Loading run state...</p> : null}
      {runState.isError ? <p className="error-text">{errorMessage(runState.error)}</p> : null}
      {runState.data ? (
        <>
          {hasStaleData ? <p className="muted-text">Showing last loaded run state.</p> : null}
          <Badge tone={statusTone(runState.data.status)}>{formatLabel(runState.data.status)}</Badge>
          <PanelRows
            rows={[
              ["Packet", runState.data.packet.title],
              ["Objective", runState.data.packetVersion.objective],
              ["Actions", listText(runState.data.allowedNextActions)],
              ["Execution", formatLabel(runState.data.run.executionState)],
              ["Verification", formatLabel(runState.data.run.verificationState)],
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
