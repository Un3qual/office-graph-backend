import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, defaultValue, enabledAffordance, submissionIdentity, targetValues } from "../commandFormSupport";
import { useRecordExecutionObservationCommand } from "../commandWorkflow";
import type { OperatorRunState } from "../workflow";

export function RunCommandForm({ onRefresh, runState }: { onRefresh: () => void; runState: OperatorRunState }) {
  const command = useRecordExecutionObservationCommand(onRefresh);
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const [rationale, setRationale] = useState("");
  const affordance = enabledAffordance(runState.commandAffordances, "record_execution_observation");

  if (!affordance) return null;

  const verificationCheckIds = targetValues(affordance, "verification_check");
  const sourceGraphItemIdForCheck = (verificationCheckId: string) =>
    runState.requiredChecks.find(check => check.verificationCheckId === verificationCheckId)?.graphItemId ?? "";

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const outcome = String(form.get("observationOutcome") ?? "");
    const input = {
      runId: defaultValue(affordance, "run_id") || runState.run.id,
      verificationCheckId: String(form.get("verificationCheckId") ?? ""),
      sourceGraphItemId: sourceGraphItemIdForCheck(String(form.get("verificationCheckId") ?? "")), observedStatus: outcome, normalizedStatus: outcome,
      observationRationale: rationale.trim(), observationSourceKind: "human",
      observationSourceIdentity: "operator-console", freshnessState: "fresh", trustBasis: "owner_attested"
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key, observationIdempotencyKey: `observation:${attempt.current.key}` });
  };

  return <form className="operator-command-form" onSubmit={submit}>
    <label htmlFor="verification-check">Verification check</label>
    <select defaultValue={verificationCheckIds[0] ?? ""} id="verification-check" name="verificationCheckId">
      {verificationCheckIds.map(id => <option key={id} value={id}>{id}</option>)}
    </select>
    <label htmlFor="observation-outcome">Observation outcome</label>
    <select defaultValue="succeeded" id="observation-outcome" name="observationOutcome">
      <option value="succeeded">Succeeded</option>
      <option value="failed">Failed</option>
    </select>
    <label htmlFor="observation-rationale">Observation rationale</label><textarea id="observation-rationale" onChange={event => setRationale(event.target.value)} value={rationale} />
    <Button isDisabled={command.state.status === "pending" || !rationale.trim() || verificationCheckIds.length === 0} type="submit" variant="primary">{command.state.status === "pending" ? "Recording observation" : "Record execution observation"}</Button>
    <FormFeedback feedback={commandFeedback(command.state)} />
  </form>;
}
