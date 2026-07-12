export {
  commandFeedback,
  defaultValue,
  defaultValues,
  enabledAffordance,
  submissionIdentity,
  targetValues
} from "../../relay/commandFormSupport";

export async function manualReplayIdentity(body: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body));
  const hash = Array.from(new Uint8Array(digest), byte =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  return `operator:${hash}`;
}
