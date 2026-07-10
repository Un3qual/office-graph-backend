import { Badge } from "../../../../src/ui/Badge";
import { Button } from "../../../../src/ui/Button";
import { Panel, PanelRows } from "../../../../src/ui/Panel";
import {
  commandAffordanceListText,
  formatLabel,
  isQueryLoading,
  listText,
  statusTone
} from "../presentation";
import type { OperatorWorkflowState } from "../workflow";

type Props = {
  onValidateReadiness: OperatorWorkflowState["validatePacketReadiness"];
  readiness: OperatorWorkflowState["readiness"];
  readinessInput: OperatorWorkflowState["readinessInput"];
  readinessQuery: OperatorWorkflowState["readinessQuery"];
};

export function ReadinessPanel({
  onValidateReadiness,
  readiness,
  readinessInput,
  readinessQuery
}: Props) {
  const isLoading = isQueryLoading(readinessQuery);
  const hasStaleData = readinessQuery.isError && Boolean(readiness);
  const isDerived = isDerivedReadiness(readiness);
  const canValidateReadiness = Boolean(isDerived && readinessInput);

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
          {canValidateReadiness ? (
            <div className="ui-panel-actions">
              <Button
                isDisabled={isLoading}
                onPress={() => {
                  onValidateReadiness();
                }}
              >
                {isLoading ? "Validating readiness" : "Validate readiness"}
              </Button>
            </div>
          ) : null}
          <PanelRows
            rows={[
              ["Mode", isDerived ? "Prepare packet context" : "Backend readiness"],
              ["Ready", readiness.ready ? "Yes" : "No"],
              [
                "Commands",
                commandAffordanceListText(
                  readiness.commandAffordances,
                  readiness.allowedNextActions
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

function isDerivedReadiness(
  readiness: OperatorWorkflowState["readiness"]
): readiness is Extract<
  NonNullable<OperatorWorkflowState["readiness"]>,
  { isDerived: true }
> {
  return readiness !== null && "isDerived" in readiness && readiness.isDerived;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Unable to load packet readiness.";
}
