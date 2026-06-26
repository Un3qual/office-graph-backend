import { describe, expect, it } from "vitest";
import { actionLabel, formatWorkflowStatus, statusTone } from "./status";

describe("operator workflow status helpers", () => {
  it("formats backend status vocabulary for console labels", () => {
    expect(formatWorkflowStatus("pending_triage")).toBe("Pending triage");
    expect(formatWorkflowStatus("ready_for_packet")).toBe("Ready for packet");
    expect(formatWorkflowStatus("awaiting_evidence_acceptance")).toBe(
      "Awaiting evidence acceptance"
    );
  });

  it("maps workflow states to stable visual tones", () => {
    expect(statusTone("pending_triage")).toBe("teal");
    expect(statusTone("packet_ready")).toBe("green");
    expect(statusTone("blocked")).toBe("amber");
    expect(statusTone("failed")).toBe("red");
  });

  it("labels backend action identifiers for buttons and disabled affordances", () => {
    expect(actionLabel("apply_proposed_changes")).toBe("Apply changes");
    expect(actionLabel("create_work_packet")).toBe("Review packet");
    expect(actionLabel("accept_evidence")).toBe("Accept evidence");
  });
});
