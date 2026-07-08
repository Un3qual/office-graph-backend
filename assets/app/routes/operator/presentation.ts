import type { BadgeTone } from "../../../src/ui/Badge";
import type { OperatorCommandAffordance, QueryState } from "./types";

export function formatLabel(value: string | null | undefined) {
  if (!value) {
    return "None";
  }

  const label = value.split("_").filter(Boolean).join(" ");

  return label.slice(0, 1).toUpperCase() + label.slice(1);
}

export function listText(values: readonly string[]) {
  return values.length > 0 ? values.map(formatLabel).join(", ") : "None";
}

export function isQueryLoading(query: Pick<QueryState<unknown>, "fetchStatus" | "isPending">) {
  return query.fetchStatus === "fetching" || (query.isPending && query.fetchStatus === "paused");
}

export function commandAffordanceListText(
  affordances: readonly OperatorCommandAffordance[],
  fallback: readonly string[]
) {
  if (affordances.length === 0) {
    return listText(fallback);
  }

  return affordances.map(commandAffordanceText).join(", ");
}

function commandAffordanceText(affordance: OperatorCommandAffordance) {
  const state = affordance.state.toLowerCase();

  if (state === "enabled") {
    return formatLabel(affordance.identity);
  }

  if (state === "disabled") {
    return [
      `${formatLabel(affordance.identity)} disabled`,
      affordance.safeExplanation,
      affordance.blockerReasons.length > 0
        ? `Blockers ${listText(affordance.blockerReasons)}`
        : null
    ]
      .filter(Boolean)
      .join(" - ");
  }

  if (state === "hidden") {
    return safeUnavailableCommandText("Hidden command", affordance.reasonCodes);
  }

  if (state === "redacted") {
    return safeUnavailableCommandText("Redacted command", affordance.reasonCodes);
  }

  return safeUnavailableCommandText("Unavailable command", affordance.reasonCodes);
}

function safeUnavailableCommandText(label: string, reasonCodes: readonly string[]) {
  const reasonText = reasonCodes.length > 0 ? listText(reasonCodes) : null;

  return reasonText ? `${label}: ${reasonText}` : label;
}

export function statusTone(status: string): BadgeTone {
  const words = new Set(status.split("_").filter(Boolean));

  if (
    (words.has("ready") && !words.has("not")) ||
    words.has("verified") ||
    words.has("passed")
  ) {
    return "green";
  }

  if (words.has("blocked") || words.has("failed") || words.has("missing") || status === "not_ready") {
    return "red";
  }

  if (words.has("awaiting") || words.has("pending")) {
    return "amber";
  }

  return "neutral";
}
