export {
  commandFeedback,
  defaultValue,
  defaultValues,
  enabledAffordance,
  submissionIdentity
} from "../../relay/commandFormSupport";

export function manualReplayIdentity(body: string) {
  let hash = 2166136261;
  for (const character of body) {
    hash ^= character.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 16777619);
  }
  return `operator:${(hash >>> 0).toString(16).padStart(8, "0")}`;
}
