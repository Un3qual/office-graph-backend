import { describe, expect, it } from "vitest";
import { graphQLInbox } from "./testSupport";
import { packetReadinessInputForItem, runIdForItem } from "./workflowDerived";
import { graphQLItem } from "./workflowMappers";

describe("operator workflow derived values", () => {
  it("builds backend packet readiness input from graph links", () => {
    const item = graphQLItem(graphQLInbox.rows[0]);

    expect(packetReadinessInputForItem(item)).toEqual({
      sourceGraphItemIds: ["graph_1"],
      verificationCheckIds: ["check_1"]
    });
  });

  it("omits work runs from packet readiness source inputs", () => {
    const item = {
      ...graphQLItem(graphQLInbox.rows[0]),
      graphLinks: [
        {
          type: "work_run",
          id: "run_1",
          graphItemId: "run_graph_1",
          title: "Run",
          state: "running"
        }
      ]
    };

    expect(packetReadinessInputForItem(item)).toEqual({
      sourceGraphItemIds: [],
      verificationCheckIds: []
    });
  });

  it("extracts the linked run id", () => {
    expect(runIdForItem(graphQLItem(graphQLInbox.rows[0]))).toBe("run_1");
  });
});
