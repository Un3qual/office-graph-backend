import type { ConcreteRequest, ReaderFragment } from "relay-runtime";
import { describe, expect, it, vi } from "vitest";

describe("operator Relay route data", () => {
  it("imports compiled Relay documents through the Vite transform path", async () => {
    const data = await import("./data");
    const routeQuery = data.OperatorWorkflowRouteQuery as ConcreteRequest;
    const itemFragment = data.OperatorWorkflowItemFragment as ReaderFragment;
    const mutation = data.ExecutePacketRunVerificationMutation as ConcreteRequest;

    expect(routeQuery.params.name).toBe("OperatorWorkflowRouteQuery");
    expect(itemFragment.name).toBe("OperatorWorkflowItemFragment");
    expect(mutation.params.operationKind).toBe("mutation");
  });

  it("invalidates operator workflow root data, run state projection, and returned run after verification", async () => {
    const data = await import("./data");
    const run = record();
    const runStateProjection = record();
    const runPayload = linkedRecord({ id: "run_1" });
    const mutationPayload = linkedRecord({ run: runPayload });
    const root = {
      invalidateRecord: vi.fn(),
      getLinkedRecord: vi.fn((fieldName: string, args?: Record<string, unknown>) =>
        fieldName === "operatorRunState" && args?.id === "run_1" ? runStateProjection : null
      )
    };
    const store = {
      getRoot: vi.fn(() => root),
      getRootField: vi.fn((fieldName: string) =>
        fieldName === "executePacketRunVerification" ? mutationPayload : null
      ),
      get: vi.fn((dataID: string) => (dataID === "run_1" ? run : null))
    };

    data.updateOperatorWorkflowAfterVerification(store as never, null);

    expect(data.operatorWorkflowRouteRootID()).toBe("client:root");
    expect(root.invalidateRecord).toHaveBeenCalledTimes(1);
    expect(root.getLinkedRecord).toHaveBeenCalledWith("operatorRunState", { id: "run_1" });
    expect(runStateProjection.invalidateRecord).toHaveBeenCalledTimes(1);
    expect(run.invalidateRecord).toHaveBeenCalledTimes(1);
  });
});

function record() {
  return {
    invalidateRecord: vi.fn()
  };
}

function linkedRecord(values: Record<string, unknown>) {
  return {
    getLinkedRecord: vi.fn((fieldName: string) => values[fieldName] ?? null),
    getValue: vi.fn((fieldName: string) => values[fieldName])
  };
}
