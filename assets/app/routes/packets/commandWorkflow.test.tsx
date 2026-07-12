import type { ReactNode } from "react";
import { act, renderHook, waitFor } from "@testing-library/react";
import { RelayEnvironmentProvider } from "react-relay";
import { Environment, Network, RecordSource, Store } from "relay-runtime";
import { describe, expect, it } from "vitest";
import { useCreateWorkPacketVersionCommand } from "./commandWorkflow";

describe("packet command workflow", () => {
  it("returns the authoritative packet and immutable version result", async () => {
    const environment = new Environment({
      getDataID: () => null,
      network: Network.create(async (request) => {
        expect(request.name).toBe("PacketsCreateWorkPacketVersionMutation");

        return {
          data: {
            createWorkPacketVersion: {
              command: "create_work_packet_version",
              operationId: "operation-2",
              affectedIds: [
                { type: "work_packet", id: "packet-1" },
                { type: "work_packet_version", id: "version-2" },
              ],
              packet: {
                id: "packet-1",
                currentVersionId: "version-2",
                title: "Revised packet",
                state: "ready",
              },
              packetVersion: {
                id: "version-2",
                versionNumber: 2,
                lifecycleState: "ready",
              },
            },
          },
        };
      }),
      store: new Store(new RecordSource()),
    });

    const { result } = renderHook(() => useCreateWorkPacketVersionCommand(), {
      wrapper: relayWrapper(environment),
    });

    act(() => {
      result.current.submit({
        idempotencyKey: "version-2",
        packetId: "packet-1",
        expectedCurrentVersionId: "version-1",
        title: "Revised packet",
        objective: "Keep the packet current.",
        contextSummary: "Current context.",
        requirements: "Preserve immutable history.",
        successCriteria: "Version two is current.",
        autonomyPosture: "human_supervised",
        sourceGraphItemIds: ["graph-item-1"],
        verificationCheckIds: ["check-1"],
      });
    });

    await waitFor(() => expect(result.current.state.status).toBe("success"));

    expect(result.current.state).toEqual({
      status: "success",
      operationId: "operation-2",
      affectedIds: [
        { type: "work_packet", id: "packet-1" },
        { type: "work_packet_version", id: "version-2" },
      ],
      result: {
        packet: {
          id: "packet-1",
          currentVersionId: "version-2",
          title: "Revised packet",
          state: "ready",
        },
        packetVersion: {
          id: "version-2",
          versionNumber: 2,
          lifecycleState: "ready",
        },
      },
    });
  });
});

function relayWrapper(environment: Environment) {
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
    );
  };
}
