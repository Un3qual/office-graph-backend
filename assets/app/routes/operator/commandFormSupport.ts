import type { CommandMutationState } from "../../relay/commandMutation";
import type { FormFeedbackMessage } from "../../../src/ui/FormFeedback";

type InputDefault = { readonly field: string; readonly value?: string | null; readonly values?: readonly string[] };
type Affordance = { readonly identity: string; readonly state: string; readonly inputDefaults: readonly InputDefault[] };

export function enabledAffordance<T extends Affordance>(affordances: readonly T[], identity: string) {
  return affordances.find(item => item.identity === identity && item.state === "enabled") ?? null;
}

export function defaultValue(affordance: Affordance, field: string) {
  return affordance.inputDefaults.find(item => item.field === field)?.value ?? "";
}

export function defaultValues(affordance: Affordance, field: string) {
  return [...(affordance.inputDefaults.find(item => item.field === field)?.values ?? [])];
}

export function commandFeedback<TResult>(state: CommandMutationState<TResult>): FormFeedbackMessage | null {
  if (state.status === "field-error") {
    const first = state.fields[0];
    return first ? { kind: "field", field: first.field, message: first.message } : null;
  }
  if (state.status === "conflict") return { kind: "conflict", message: state.message };
  if (state.status === "error") return { kind: "error", message: state.message };
  return null;
}

export function submissionIdentity(previous: { fingerprint: string; key: string } | null, input: unknown) {
  const fingerprint = JSON.stringify(input);
  return previous?.fingerprint === fingerprint
    ? previous
    : { fingerprint, key: crypto.randomUUID() };
}

export function manualReplayIdentity(body: string) {
  let hash = 2166136261;
  for (const character of body) {
    hash ^= character.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 16777619);
  }
  return `operator:${(hash >>> 0).toString(16).padStart(8, "0")}`;
}
