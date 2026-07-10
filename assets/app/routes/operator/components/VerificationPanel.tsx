import { Badge } from "../../../../src/ui/Badge";
import { Panel, PanelRows } from "../../../../src/ui/Panel";
import { formatLabel, statusTone } from "../presentation";
import type { OperatorWorkflowState } from "../workflow";

type Props = {
  verification: OperatorWorkflowState["verification"];
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

function verificationResultText(
  result: NonNullable<
    OperatorWorkflowState["verification"]
  >["verificationResults"][number]
) {
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
