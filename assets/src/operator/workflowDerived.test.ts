import { describe, expect, it } from "vitest";
import { graphQLInbox } from "./testSupport";
import { packetReadinessForLoadedItem } from "./workflowDerived";
import { graphQLItem } from "./workflowMappers";

describe("operator workflow derived projections", () => {
  it("marks locally complete packet readiness as ready", () => {
    const item = {
      ...graphQLItem(graphQLInbox.rows[0]),
      allowedNextActions: ["prepare_packet"],
      status: "ready_for_packet"
    };

    expect(packetReadinessForLoadedItem(item)).toMatchObject({
      ready: true,
      status: "ready_for_packet",
      blockerReasons: [],
      isDerived: true
    });
  });

  it("defers to backend readiness when local packet context is incomplete", () => {
    const item = {
      ...graphQLItem(graphQLInbox.rows[0]),
      graphLinks: [],
      allowedNextActions: ["prepare_packet"],
      status: "ready_for_packet"
    };

    expect(packetReadinessForLoadedItem(item)).toBeNull();
  });
});
