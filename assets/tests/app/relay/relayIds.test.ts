import { describe, expect, it } from "vitest";
import {
  relayGlobalId,
  relayInternalId,
  translateRelayMutationInput,
} from "../../../app/relay/relayIds";

describe("Relay ID boundaries", () => {
  it("encodes scalar and list mutation fields without changing unrelated input", () => {
    expect(
      translateRelayMutationInput(
        {
          idempotencyKey: "command-1",
          runId: "run-1",
          sourceGraphItemIds: ["graph-item-1"],
        },
        {
          runId: "work_run",
          sourceGraphItemIds: "graph_item",
        },
      ),
    ).toEqual({
      idempotencyKey: "command-1",
      runId: "d29ya19ydW46cnVuLTE=",
      sourceGraphItemIds: ["Z3JhcGhfaXRlbTpncmFwaC1pdGVtLTE="],
    });
  });

  it("keeps correctly typed Relay IDs stable at repeated boundaries", () => {
    const runId = "d29ya19ydW46cnVuLTE=";

    expect(relayGlobalId("work_run", runId)).toBe(runId);
    expect(relayInternalId("work_run", runId)).toBe("run-1");
  });

  it("rejects a Relay ID for the wrong resource type", () => {
    expect(() => relayGlobalId("graph_item", "d29ya19ydW46cnVuLTE=")).toThrow(
      "Expected a graph_item Relay ID, received work_run.",
    );
  });
});
