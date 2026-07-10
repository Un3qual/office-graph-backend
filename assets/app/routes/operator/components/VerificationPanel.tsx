import { Badge } from "../../../../src/ui/Badge";
import { Panel, PanelRows } from "../../../../src/ui/Panel";
import { formatLabel, statusTone } from "../presentation";
import type { verificationOutcomeFromRunState } from "../derived";

type Verification = ReturnType<typeof verificationOutcomeFromRunState>;

type Props = {
  state: "empty" | "error" | "loaded" | "loading";
  verification: Verification | null;
};

export function VerificationPanel({ state, verification }: Props) {
  return (
    <Panel ariaLabel="Verification">
      <h2>Verification</h2>
      {state === "empty" ? <p>No verification outcome selected.</p> : null}
      {state === "loading" ? <p>Loading verification...</p> : null}
      {state === "error" ? <p className="error-text">Verification unavailable.</p> : null}
      {state === "loaded" && verification ? (
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
  result: Verification["verificationResults"][number]
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
