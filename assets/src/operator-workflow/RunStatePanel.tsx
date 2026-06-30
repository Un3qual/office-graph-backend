import { Panel, PanelRows } from "../ui/Panel";
import type { OperatorRunState } from "./api";
import {
  formatEvidenceCandidateDetails,
  formatObservationDetails
} from "./formatters";
import type { Loadable } from "./loadable";
import { actionLabel, formatWorkflowStatus } from "./status";

type Props = {
  runState: Loadable<OperatorRunState>;
};

export function RunStatePanel({ runState }: Props) {
  return (
    <Panel ariaLabel="Run State">
      <h2>Run State</h2>
      {runState.state === "loading" ? <p>Loading run state...</p> : null}
      {runState.state === "idle" ? <p>No run linked yet.</p> : null}
      {runState.state === "error" ? <p className="error-text">{runState.message}</p> : null}
      {runState.state === "loaded" ? (
        <PanelRows
          rows={[
            ["Status", formatWorkflowStatus(runState.data.status)],
            ["Run ID", runState.data.run.id],
            ["Execution", formatWorkflowStatus(runState.data.run.execution_state)],
            ["Required checks", String(runState.data.required_checks.length)],
            ["Actions", runState.data.allowed_next_actions.map(actionLabel).join(", ") || "None"],
            ["Observations", formatObservationDetails(runState.data.observations)],
            ["Evidence candidates", formatEvidenceCandidateDetails(runState.data.evidence_candidates)],
            ["Verification results", String(runState.data.verification_results.length)],
            [
              "Missing evidence",
              runState.data.missing_evidence
                .map((item) => String(item.reason ?? "missing"))
                .join(", ") || "None"
            ]
          ]}
        />
      ) : null}
    </Panel>
  );
}
