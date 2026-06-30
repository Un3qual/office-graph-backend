import { Panel, PanelRows } from "../ui/Panel";
import type { VerificationOutcome } from "./api";
import { formatVerificationResultDetails } from "./formatters";
import type { Loadable } from "./loadable";
import { formatWorkflowStatus } from "./status";

type Props = {
  verification: Loadable<VerificationOutcome>;
};

export function VerificationPanel({ verification }: Props) {
  return (
    <Panel ariaLabel="Verification">
      <h2>Verification</h2>
      {verification.state === "loading" ? <p>Loading verification...</p> : null}
      {verification.state === "idle" ? <p>No verification outcome selected.</p> : null}
      {verification.state === "error" ? <p className="error-text">{verification.message}</p> : null}
      {verification.state === "loaded" ? (
        <PanelRows
          rows={[
            ["Status", formatWorkflowStatus(verification.data.status)],
            ["Run ID", verification.data.run.id],
            ["Accepted evidence", String(verification.data.verification_results.length)],
            ["Results", formatVerificationResultDetails(verification.data.verification_results)],
            [
              "Missing evidence",
              verification.data.missing_evidence
                .map((item) => String(item.reason ?? "missing"))
                .join(", ") || "None"
            ]
          ]}
        />
      ) : null}
    </Panel>
  );
}
