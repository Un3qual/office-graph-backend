type Tone = "teal" | "green" | "amber" | "blue" | "red" | "neutral";

const statusLabels: Record<string, string> = {
  awaiting_evidence: "Awaiting evidence",
  awaiting_evidence_acceptance: "Awaiting evidence acceptance",
  awaiting_execution: "Awaiting execution",
  blocked: "Blocked",
  failed: "Failed",
  not_actionable: "Not actionable",
  packet_ready: "Packet ready",
  pending_triage: "Pending triage",
  ready_for_packet: "Ready for packet",
  verified: "Verified"
};

const statusTones: Record<string, Tone> = {
  awaiting_evidence: "blue",
  awaiting_evidence_acceptance: "amber",
  awaiting_execution: "blue",
  blocked: "amber",
  failed: "red",
  not_actionable: "neutral",
  packet_ready: "green",
  pending_triage: "teal",
  ready_for_packet: "green",
  verified: "green"
};

const actionLabels: Record<string, string> = {
  accept_evidence: "Accept evidence",
  apply_proposed_changes: "Apply changes",
  create_work_packet: "Review packet",
  prepare_packet: "Prepare packet",
  record_evidence: "Record evidence",
  start_run: "Start run"
};

export function formatWorkflowStatus(status: string) {
  return statusLabels[status] ?? fallbackLabel(status);
}

export function actionLabel(action: string) {
  return actionLabels[action] ?? fallbackLabel(action);
}

export function statusTone(status: string): Tone {
  return statusTones[status] ?? "neutral";
}

function fallbackLabel(value: string) {
  const normalized = value.replaceAll("_", " ").trim();

  if (normalized.length === 0) {
    return "Unknown";
  }

  return normalized[0].toUpperCase() + normalized.slice(1);
}
