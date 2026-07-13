import { Badge } from "../../../../src/ui/Badge";
import { Panel, PanelRows } from "../../../../src/ui/Panel";
import { Button } from "../../../../src/ui/Button";
import { commandAffordanceListText, formatLabel, statusTone } from "../presentation";
import type { OperatorRunState } from "../workflow";

type Props = {
  runId: string | null;
  runState: OperatorRunState | null;
  state: "empty" | "error" | "loaded" | "loading";
  onNextActivityPage?: () => void;
  onPreviousActivityPage?: () => void;
};

export function RunPanel({
  onNextActivityPage,
  onPreviousActivityPage,
  runId,
  runState,
  state,
}: Props) {
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
                commandAffordanceListText(runState.commandAffordances, runState.allowedNextActions),
              ],
              ["Execution", formatLabel(runState.run.executionState)],
              ["Verification", formatLabel(runState.run.verificationState)],
              [
                "Run activity",
                `${runState.childSummary.requiredChecks} checks · ${runState.childSummary.observations} observations · ${runState.childSummary.evidenceCandidates} evidence suggestions${runState.childSummary.hasMore ? " · more available" : ""}`,
              ],
              [
                "Required checks",
                runState.requiredChecks
                  .map(
                    (check) =>
                      `${check.verificationCheckId ?? "unknown"}: ${formatLabel(check.state)}`,
                  )
                  .join(", ") || "None",
              ],
              [
                "Suggested evidence",
                runState.evidenceCandidates.map((candidate) => candidate.claim).join(", ") ||
                  "None",
              ],
              [
                "Observations",
                runState.observations
                  .map(
                    (observation) =>
                      `${formatLabel(observation.normalizedStatus)} · ${formatLabel(
                        observation.freshnessState,
                      )} · ${formatLabel(observation.trustBasis)} · ${observation.sourceIdentity}`,
                  )
                  .join(", ") || "None",
              ],
            ]}
          />
          <ul aria-label="Run activity detail">
            {(runState.activity?.edges ?? []).flatMap((edge) =>
              edge?.node
                ? [
                    <li key={`${edge.node.kind}:${edge.node.stableId}`}>
                      {edge.node.title} · {formatLabel(edge.node.status)}
                    </li>,
                  ]
                : [],
            )}
          </ul>
          <div aria-label="Run activity pagination">
            {runState.activity?.pageInfo.hasPreviousPage && onPreviousActivityPage ? (
              <Button onPress={onPreviousActivityPage}>Previous run activity page</Button>
            ) : null}
            {runState.activity?.pageInfo.hasNextPage && onNextActivityPage ? (
              <Button onPress={onNextActivityPage}>Next run activity page</Button>
            ) : null}
          </div>
        </>
      ) : null}
    </Panel>
  );
}
