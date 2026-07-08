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

export function enabledCommandIdentities(
  affordances: readonly OperatorCommandAffordance[],
  fallback: readonly string[]
) {
  const enabled = affordances
    .filter((affordance) => affordance.state === "enabled")
    .map((affordance) => affordance.identity);

  return enabled.length > 0 ? enabled : fallback;
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
