import type { ReactNode } from "react";
import { act, renderHook, waitFor } from "@testing-library/react";
import { RelayEnvironmentProvider } from "react-relay";
import {
  Environment,
  Network,
  RecordSource,
  Store,
  type GraphQLResponse,
  type Variables
} from "relay-runtime";
import { describe, expect, it } from "vitest";
import { useSubmitManualIntakeCommand } from "./commandWorkflow";

describe("operator command workflow", () => {
  it("moves from idle through pending to the typed success result", async () => {
    const request = deferredRequest();
    const environment = relayEnvironment(request.fetch);
    const { result } = renderHook(() => useSubmitManualIntakeCommand(), {
      wrapper: relayWrapper(environment)
    });

    expect(result.current.state).toEqual({ status: "idle" });

    act(() => {
      result.current.submit({
        idempotencyKey: "intake-1",
        sourceIdentity: "manual:test",
        replayIdentity: "paste:test",
        body: "Create a durable intake event."
      });
    });

    expect(result.current.state).toEqual({ status: "pending" });
    expect(request.name).toBe("OperatorSubmitManualIntakeMutation");
    expect(request.variables).toEqual({
      input: {
        idempotencyKey: "intake-1",
        sourceIdentity: "manual:test",
        replayIdentity: "paste:test",
        body: "Create a durable intake event."
      }
    });

    act(() => {
      request.resolve({
        data: {
          submitManualIntake: {
            command: "submit_manual_intake",
            operationId: "operation-1",
            affectedIds: [{ type: "normalized_intake_event", id: "event-1" }],
            normalizedEventId: "event-1",
            proposedChangeIds: ["proposal-1"]
          }
        }
      });
    });

    await waitFor(() => expect(result.current.state.status).toBe("success"));

    expect(result.current.state).toEqual({
      status: "success",
      operationId: "operation-1",
      affectedIds: [{ type: "normalized_intake_event", id: "event-1" }],
      result: {
        normalizedEventId: "event-1",
        proposedChangeIds: ["proposal-1"]
      }
    });

    act(() => result.current.reset());
    expect(result.current.state).toEqual({ status: "idle" });
  });
});

function deferredRequest() {
  let resolveResponse: (response: GraphQLResponse) => void = () => undefined;
  let name: string | null = null;
  let variables: Variables | null = null;

  return {
    fetch(request: { name: string }, nextVariables: Variables) {
      name = request.name;
      variables = nextVariables;
      return new Promise<GraphQLResponse>(resolve => {
        resolveResponse = resolve;
      });
    },
    get name() {
      return name;
    },
    get variables() {
      return variables;
    },
    resolve(response: GraphQLResponse) {
      resolveResponse(response);
    }
  };
}

function relayEnvironment(fetch: ReturnType<typeof deferredRequest>["fetch"]) {
  return new Environment({
    getDataID: () => null,
    network: Network.create(fetch),
    store: new Store(new RecordSource())
  });
}

function relayWrapper(environment: Environment) {
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <RelayEnvironmentProvider environment={environment}>
        {children}
      </RelayEnvironmentProvider>
    );
  };
}
