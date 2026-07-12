import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, enabledAffordance, submissionIdentity } from "../commandFormSupport";
import { useRecordExecutionObservationCommand } from "../commandWorkflow";
import type { OperatorRunState } from "../workflow";

export function RunCommandForm({ onRefresh, runState }: { onRefresh: () => void; runState: OperatorRunState }) {
  const command = useRecordExecutionObservationCommand(onRefresh);
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const [rationale, setRationale] = useState("");
  const [selectedOptionKey, setSelectedOptionKey] = useState("");
  const [selectedOutcomeKey, setSelectedOutcomeKey] = useState("");
  const affordance = enabledAffordance(runState.commandAffordances, "record_execution_observation");

  if (!affordance) return null;

  const options = runState.commandOptions.observation.filter((option) =>
    completeOption(option, [
      "key",
      "label",
      "runId",
      "verificationCheckId",
      "sourceGraphItemId",
      "observationSourceKind",
      "observationSourceIdentity",
      "freshnessState",
      "trustBasis",
      "defaultOutcomeKey"
    ])
  );
  const currentOption = options.find(({ key }) => key === selectedOptionKey) ?? options[0];
  const currentOutcomeKey = selectedOutcomeKey || currentOption?.defaultOutcomeKey || "";

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const option = currentOption;
    if (!option) return;
    const outcome = option.outcomes.find(({ key }) => key === currentOutcomeKey);
    if (!outcome) return;
    const input = {
      runId: option.runId,
      verificationCheckId: option.verificationCheckId,
      sourceGraphItemId: option.sourceGraphItemId,
      observedStatus: outcome.observedStatus,
      normalizedStatus: outcome.normalizedStatus,
      observationRationale: rationale.trim(),
      observationSourceKind: option.observationSourceKind,
      observationSourceIdentity: option.observationSourceIdentity,
      freshnessState: option.freshnessState,
      trustBasis: option.trustBasis
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key, observationIdempotencyKey: `observation:${attempt.current.key}` });
  };

  return <form className="operator-command-form" onSubmit={submit}>
    <label htmlFor="verification-check">Verification check</label>
    <select id="verification-check" name="observationOptionKey" onChange={event => {
      setSelectedOptionKey(event.target.value);
      setSelectedOutcomeKey("");
    }} value={currentOption?.key ?? ""}>
      {options.map(option => <option key={option.key} value={option.key}>{option.label}</option>)}
    </select>
    <label htmlFor="observation-outcome">Observation outcome</label>
    <select id="observation-outcome" name="observationOutcomeKey" onChange={event => setSelectedOutcomeKey(event.target.value)} value={currentOutcomeKey}>
      {(currentOption?.outcomes ?? []).map(outcome => <option key={outcome.key} value={outcome.key}>{outcome.label}</option>)}
    </select>
    <label htmlFor="observation-rationale">Observation rationale</label><textarea id="observation-rationale" onChange={event => setRationale(event.target.value)} value={rationale} />
    <Button isDisabled={command.state.status === "pending" || !rationale.trim() || options.length === 0} type="submit" variant="primary">{command.state.status === "pending" ? "Recording observation" : "Record execution observation"}</Button>
    <FormFeedback feedback={commandFeedback(command.state)} />
  </form>;
}

function completeOption(option: object, fields: string[]) {
  const values = option as Record<string, unknown>;
  return fields.every((field) => usableProjectionValue(values[field])) &&
    Array.isArray(values.outcomes) && values.outcomes.every(outcome =>
      typeof outcome === "object" && outcome !== null &&
      ["key", "label", "observedStatus", "normalizedStatus"].every(field =>
        usableProjectionValue((outcome as Record<string, unknown>)[field])
      )
    );
}

function usableProjectionValue(value: unknown) {
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized !== "" && !["[redacted]", "<redacted>", "redacted", "***"].includes(normalized);
}
