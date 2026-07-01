import { Badge } from "../../ui/Badge";
import { Panel, PanelRows } from "../../ui/Panel";
import type { VerificationOutcome } from "../workflowTypes";
import { formatLabel, statusTone } from "../workflowPresentation";

type Props = {
  verification: VerificationOutcome | null;
};

export function VerificationPanel({ verification }: Props) {
  return (
    <Panel ariaLabel="Verification">
      <h2>Verification</h2>
      {!verification ? <p>No verification outcome selected.</p> : null}
      {verification ? (
        <>
          <Badge tone={statusTone(verification.status)}>{formatLabel(verification.status)}</Badge>
          <PanelRows
            rows={[
              [
                "Verification decisions",
                verification.verificationResults
                  .map((result) => verificationResultText(result))
                  .join(", ") || "None"
              ],
              [
                "Missing evidence",
                verification.missingEvidence
                  .map((evidence) => `${evidence.verificationCheckId}: ${evidence.reason}`)
                  .join(", ") || "None"
              ]
            ]}
          />
        </>
      ) : null}
    </Panel>
  );
}

function verificationResultText(result: VerificationOutcome["verificationResults"][number]) {
  return [
    formatLabel(result.result),
    result.policyBasis ? formatLabel(result.policyBasis) : null,
    result.operationId ? `Operation ${result.operationId}` : null,
    result.actorPrincipalId ? `Actor ${result.actorPrincipalId}` : null,
    result.targetGraphItemId ? `Target ${result.targetGraphItemId}` : null
  ]
    .filter(Boolean)
    .join(" · ");
}
