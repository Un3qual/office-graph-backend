import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { CommandFieldError, CommandFormFeedback } from "../../../relay/CommandFormFeedback";
import { commandFieldErrorProps, enabledAffordance, submissionIdentity } from "../commandFormSupport";
import { useRecordExecutionObservationCommand } from "../commandWorkflow";
import type { OperatorRunState } from "../workflow";

export function RunCommandForm({ onRefresh, runState }: { onRefresh: () => void; runState: OperatorRunState }) {
  const command = useRecordExecutionObservationCommand(onRefresh);
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const formRef = useRef<HTMLFormElement>(null);
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

  return <form className="operator-command-form" onSubmit={submit} ref={formRef}>
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
    <label htmlFor="observation-rationale">Observation rationale</label>
    <textarea
      {...commandFieldErrorProps(command.state, "record-observation", "observationRationale")}
      id="observation-rationale"
      name="observationRationale"
      onChange={event => setRationale(event.target.value)}
      value={rationale}
    />
    <CommandFieldError controlName="observationRationale" scope="record-observation" state={command.state} />
    <Button isDisabled={command.state.status === "pending" || !rationale.trim() || options.length === 0} type="submit" variant="primary">{command.state.status === "pending" ? "Recording observation" : "Record execution observation"}</Button>
    <CommandFormFeedback formRef={formRef} scope="record-observation" state={command.state} />
  </form>;
}

function completeOption(option: object, fields: string[]) {
  const outcomesValue = objectValue(option, "outcomes");
  if (!fields.every((field) => usableProjectionValue(objectValue(option, field))) ||
      !Array.isArray(outcomesValue) || outcomesValue.length === 0) return false;

  const outcomes: unknown[] = outcomesValue;
  const keys = outcomes.map(outcome =>
    typeof outcome === "object" && outcome !== null
      ? objectValue(outcome, "key")
      : null
  );

  return new Set(keys).size === keys.length &&
    keys.includes(objectValue(option, "defaultOutcomeKey")) && outcomes.every(outcome =>
      typeof outcome === "object" && outcome !== null &&
      ["key", "label", "observedStatus", "normalizedStatus"].every(field =>
        usableProjectionValue(objectValue(outcome, field))
      )
    );
}

function objectValue(value: object, field: string): unknown {
  return Object.getOwnPropertyDescriptor(value, field)?.value;
}

function usableProjectionValue(value: unknown) {
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized !== "" && !["[redacted]", "<redacted>", "redacted", "***"].includes(normalized);
}
