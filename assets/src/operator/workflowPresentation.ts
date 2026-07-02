import type { FetchStatus } from "@tanstack/react-query";
import type { BadgeTone } from "../ui/Badge";

export function formatLabel(value: string | null | undefined) {
  if (!value) {
    return "None";
  }

  const label = value.split("_").filter(Boolean).join(" ");

  return label.slice(0, 1).toUpperCase() + label.slice(1);
}

export function listText(values: string[]) {
  return values.length > 0 ? values.map(formatLabel).join(", ") : "None";
}

export function isQueryLoading(query: { fetchStatus: FetchStatus; isPending: boolean }) {
  return query.fetchStatus === "fetching" || (query.isPending && query.fetchStatus === "paused");
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
