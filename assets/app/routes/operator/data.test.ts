import { ConnectionHandler, type ConcreteRequest, type ReaderFragment, type RecordProxy } from "relay-runtime";
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

  it("invalidates the operator workflow connection and returned run after verification", async () => {
    const data = await import("./data");
    const connection = record();
    const run = record();
    const runPayload = linkedRecord({ id: "run_1" });
    const mutationPayload = linkedRecord({ run: runPayload });
    const root = {
      getDataID: vi.fn(() => "client:root")
    };
    const store = {
      getRoot: vi.fn(() => root),
      getRootField: vi.fn((fieldName: string) =>
        fieldName === "executePacketRunVerification" ? mutationPayload : null
      ),
      get: vi.fn((dataID: string) => (dataID === "run_1" ? run : null))
    };

    const getConnectionSpy = vi
      .spyOn(ConnectionHandler, "getConnection")
      .mockReturnValue(connection as unknown as RecordProxy);

    data.updateOperatorWorkflowAfterVerification(store as never, null);

    expect(getConnectionSpy).toHaveBeenCalledWith(root, data.operatorWorkflowConnectionKey);
    expect(connection.invalidateRecord).toHaveBeenCalledTimes(1);
    expect(run.invalidateRecord).toHaveBeenCalledTimes(1);

    getConnectionSpy.mockRestore();
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
