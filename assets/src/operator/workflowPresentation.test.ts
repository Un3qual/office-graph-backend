import { describe, expect, it } from "vitest";
import { statusTone } from "./workflowPresentation";

describe("operator workflow presentation", () => {
  it("maps status tones from exact status words", () => {
    expect(statusTone("ready_for_packet")).toBe("green");
    expect(statusTone("unblocked")).toBe("neutral");
    expect(statusTone("not_ready")).toBe("red");
    expect(statusTone("awaiting_evidence_acceptance")).toBe("amber");
    expect(statusTone("missing_source_graph_items")).toBe("red");
  });
});
