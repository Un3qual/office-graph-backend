import type { ConcreteRequest, ReaderFragment } from "relay-runtime";
import { describe, expect, it } from "vitest";

describe("operator Relay route data", () => {
  it("imports compiled Relay documents through the Vite transform path", async () => {
    const data = await import("./data");
    const routeQuery = data.OperatorWorkflowRouteQuery as ConcreteRequest;
    const itemFragment = data.OperatorWorkflowItemFragment as ReaderFragment;
    const readinessQuery = data.OperatorPacketReadinessQuery as ConcreteRequest;
    const runStateQuery = data.OperatorRunStateQuery as ConcreteRequest;

    expect(routeQuery.params.name).toBe("OperatorWorkflowRouteQuery");
    expect(itemFragment.name).toBe("OperatorWorkflowItemFragment");
    expect(readinessQuery.params.name).toBe("OperatorPacketReadinessQuery");
    expect(runStateQuery.params.name).toBe("OperatorRunStateQuery");
  });
});
