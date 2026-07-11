import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, defaultValue, enabledAffordance, submissionIdentity } from "../commandFormSupport";
import { useRecordExecutionObservationCommand } from "../commandWorkflow";
import type { OperatorRunState } from "../workflow";

export function RunCommandForm({ onRefresh, runState }: { onRefresh: () => void; runState: OperatorRunState }) {
  const command = useRecordExecutionObservationCommand(onRefresh);
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const [rationale, setRationale] = useState("");
  const [sourceGraphItemId, setSourceGraphItemId] = useState("");
  const affordance = enabledAffordance(runState.commandAffordances, "record_execution_observation");

  if (!affordance) return null;

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const input = {
      runId: defaultValue(affordance, "run_id") || runState.run.id,
      verificationCheckId: runState.missingEvidence[0]?.verificationCheckId ?? runState.requiredChecks[0]?.verificationCheckId ?? "",
      sourceGraphItemId: sourceGraphItemId.trim(), observedStatus: "succeeded", normalizedStatus: "succeeded",
      observationRationale: rationale.trim(), observationSourceKind: "human",
      observationSourceIdentity: "operator-console", freshnessState: "fresh", trustBasis: "owner_attested"
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key, observationIdempotencyKey: `observation:${attempt.current.key}` });
  };

  return <form className="operator-command-form" onSubmit={submit}>
    <label htmlFor="observation-source">Source graph item ID</label><input id="observation-source" onChange={event => setSourceGraphItemId(event.target.value)} value={sourceGraphItemId} />
    <label htmlFor="observation-rationale">Observation rationale</label><textarea id="observation-rationale" onChange={event => setRationale(event.target.value)} value={rationale} />
    <Button isDisabled={command.state.status === "pending" || !sourceGraphItemId.trim() || !rationale.trim()} type="submit" variant="primary">{command.state.status === "pending" ? "Recording observation" : "Record execution observation"}</Button>
    <FormFeedback feedback={commandFeedback(command.state)} />
  </form>;
}
