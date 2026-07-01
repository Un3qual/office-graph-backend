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

export function statusTone(status: string): BadgeTone {
  if (status.includes("ready") || status.includes("verified") || status.includes("passed")) {
    return "green";
  }

  if (status.includes("blocked") || status.includes("failed") || status.includes("missing")) {
    return "red";
  }

  if (status.includes("awaiting") || status.includes("pending")) {
    return "amber";
  }

  return "neutral";
}
