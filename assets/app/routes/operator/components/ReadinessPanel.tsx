import { Badge } from "../../../../src/ui/Badge";
import { Button } from "../../../../src/ui/Button";
import { Panel, PanelRows } from "../../../../src/ui/Panel";
import { commandAffordanceListText, formatLabel, listText, statusTone } from "../presentation";
import type { PacketReadinessInput } from "../types";
import type { PacketReadinessState } from "../workflow";

type Props = {
  isValidating?: boolean;
  onValidateReadiness?: () => void;
  readiness: PacketReadinessState | null;
  readinessInput: PacketReadinessInput | null;
};

export function ReadinessPanel({
  isValidating = false,
  onValidateReadiness,
  readiness,
  readinessInput,
}: Props) {
  const isDerived = isDerivedReadiness(readiness);
  const canShowValidation = Boolean(
    isDerived && readinessInput && (onValidateReadiness || isValidating),
  );

  return (
    <Panel ariaLabel="Packet Readiness">
      <h2>Packet Readiness</h2>
      {!readiness ? <p>No packet readiness selected.</p> : null}
      {readiness ? (
        <>
          <Badge tone={statusTone(readiness.status)}>{formatLabel(readiness.status)}</Badge>
          {canShowValidation ? (
            <div className="ui-panel-actions">
              <Button isDisabled={isValidating} onPress={() => onValidateReadiness?.()}>
                {isValidating ? "Validating readiness" : "Validate readiness"}
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
                  readiness.allowedNextActions,
                ),
              ],
              ["Blockers", listText(readiness.blockerReasons)],
              ["Objective", readinessInput?.objective || "None"],
              ["Context", readinessInput?.contextSummary || "None"],
              ["Success criteria", readinessInput?.successCriteria || "None"],
              ["Autonomy", formatLabel(readinessInput?.autonomyPosture)],
              ["Sources", readiness.sourceLinks.map((link) => link.title).join(", ") || "None"],
              [
                "Required checks",
                readiness.requiredChecks.map((check) => formatLabel(check.state)).join(", ") ||
                  "None",
              ],
            ]}
          />
        </>
      ) : null}
    </Panel>
  );
}

export function ReadinessPanelError({ onRetry }: { onRetry: () => void }) {
  return (
    <Panel ariaLabel="Packet Readiness">
      <h2>Packet Readiness</h2>
      <p className="error-text" role="alert">
        Unable to validate packet readiness.
      </p>
      <Button onPress={onRetry}>Retry packet readiness</Button>
    </Panel>
  );
}

function isDerivedReadiness(
  readiness: PacketReadinessState | null,
): readiness is Extract<PacketReadinessState, { isDerived: true }> {
  return readiness !== null && "isDerived" in readiness && readiness.isDerived;
}
