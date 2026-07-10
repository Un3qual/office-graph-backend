import { act, createElement, type ReactNode } from "react";
import { renderHook, waitFor } from "@testing-library/react";
import { RelayEnvironmentProvider } from "react-relay";
import {
  Environment,
  Network,
  Observable,
  RecordSource,
  Store,
  type FetchFunction,
  type GraphQLResponse
} from "relay-runtime";
import { describe, expect, it, vi } from "vitest";
import { getOfficeGraphDataID } from "../../relay/environment";
import { usePacketsWorkflow } from "./workflow";

describe("packet route workflow", () => {
  it("maps empty and populated connections and keeps selection local", async () => {
    const emptyWorkflow = renderWorkflow(packetNetwork([]));

    await waitFor(() => expect(emptyWorkflow.result.current.packetQuery.isSuccess).toBe(true));
    expect(emptyWorkflow.result.current.rows).toEqual([]);
    expect(emptyWorkflow.result.current.selectedPacket).toBeNull();

    emptyWorkflow.unmount();

    const populatedWorkflow = renderWorkflow(
      packetNetwork([packet(), packet({ id: "packet_2", title: "Second packet" })])
    );

    await waitFor(() => {
      expect(populatedWorkflow.result.current.rows).toEqual([
        {
          id: "packet_1",
          title: "First packet",
          state: "active",
          currentVersionId: "version_1",
          operationId: "operation_1",
          updatedAt: "2026-07-09T12:00:00Z"
        },
        {
          id: "packet_2",
          title: "Second packet",
          state: "active",
          currentVersionId: "version_1",
          operationId: "operation_1",
          updatedAt: "2026-07-09T12:00:00Z"
        }
      ]);
      expect(populatedWorkflow.result.current.selectedPacket?.id).toBe("packet_1");
    });

    act(() => populatedWorkflow.result.current.selectPacket("packet_2"));

    expect(populatedWorkflow.result.current.selectedPacket?.id).toBe("packet_2");
  });

  it("uses Relay cursors for next and previous pages and rehomes selection", async () => {
    const firstPacket = packet();
    const secondPacket = packet({ id: "packet_2", title: "Second packet" });
    const network = vi.fn(async (_request, variables): Promise<GraphQLResponse> =>
      variables.after === "cursor_1"
        ? packetConnectionResponse([secondPacket], {
            hasNextPage: false,
            hasPreviousPage: true,
            startCursor: "cursor_2",
            endCursor: "cursor_2"
          })
        : packetConnectionResponse([firstPacket], {
            hasNextPage: true,
            hasPreviousPage: false,
            startCursor: "cursor_1",
            endCursor: "cursor_1"
          })
    );
    const workflow = renderWorkflow(network);

    await waitFor(() => {
      expect(workflow.result.current.selectedPacket?.id).toBe("packet_1");
      expect(workflow.result.current.packetQuery.data?.hasNextPage).toBe(true);
      expect(workflow.result.current.packetQuery.data?.hasPreviousPage).toBe(false);
      expect(workflow.result.current.canPageBackward).toBe(false);
    });

    act(() => workflow.result.current.loadNextPage());

    await waitFor(() => {
      expect(network.mock.lastCall?.[1]).toEqual({ first: 50, after: "cursor_1" });
      expect(workflow.result.current.selectedPacket?.id).toBe("packet_2");
      expect(workflow.result.current.packetQuery.data?.hasNextPage).toBe(false);
      expect(workflow.result.current.packetQuery.data?.hasPreviousPage).toBe(true);
      expect(workflow.result.current.canPageBackward).toBe(true);
    });

    act(() => workflow.result.current.loadPreviousPage());

    await waitFor(() => {
      expect(network.mock.lastCall?.[1]).toEqual({ first: 50, after: null });
      expect(workflow.result.current.selectedPacket?.id).toBe("packet_1");
      expect(workflow.result.current.canPageBackward).toBe(false);
    });
  });

  it("invalidates the prior connection and selection when pagination fails", async () => {
    const network = vi.fn(async (_request, variables): Promise<GraphQLResponse> => {
      if (variables.after === "cursor_1") {
        throw new Error("authorization policy secret_alpha denied packet_9");
      }

      return packetConnectionResponse([packet()], {
        hasNextPage: true,
        endCursor: "cursor_1"
      });
    });
    const workflow = renderWorkflow(network);

    await waitFor(() => {
      expect(workflow.result.current.selectedPacket?.id).toBe("packet_1");
      expect(workflow.result.current.packetQuery.data?.hasNextPage).toBe(true);
    });

    act(() => workflow.result.current.loadNextPage());

    await waitFor(() => expect(workflow.result.current.packetQuery.isError).toBe(true));
    expect(workflow.result.current.packetQuery.error?.message).toBe("Unable to load packets.");
    expect(workflow.result.current.packetQuery.data).toBeNull();
    expect(workflow.result.current.rows).toEqual([]);
    expect(workflow.result.current.selectedId).toBeNull();
    expect(workflow.result.current.selectedPacket).toBeNull();
    expect(workflow.result.current.canPageBackward).toBe(false);
  });

  it("normalizes Relay failures without exposing server details", async () => {
    const workflow = renderWorkflow(
      vi.fn(async () => {
        throw new Error("authorization policy bundle secret_alpha denied packet_9");
      })
    );

    await waitFor(() => expect(workflow.result.current.packetQuery.isError).toBe(true));
    expect(workflow.result.current.packetQuery.error?.message).toBe("Unable to load packets.");
    expect(workflow.result.current.packetQuery.error?.message).not.toMatch(/secret_alpha|packet_9/);
  });

  it("unsubscribes from the Relay observable when the route workflow unmounts", async () => {
    const didUnsubscribe = vi.fn();
    const network: FetchFunction = () =>
      Observable.create(() => {
        return () => didUnsubscribe();
      });
    const workflow = renderWorkflow(network);

    await act(async () => undefined);
    workflow.unmount();

    expect(didUnsubscribe).toHaveBeenCalledOnce();
  });
});

function renderWorkflow(network: FetchFunction) {
  const environment = new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(network),
    store: new Store(new RecordSource())
  });

  return renderHook(() => usePacketsWorkflow(), {
    wrapper: ({ children }: { children: ReactNode }) =>
      createElement(RelayEnvironmentProvider, { environment, children })
  });
}

function packetNetwork(packets: ReturnType<typeof packet>[]) {
  return vi.fn(async (): Promise<GraphQLResponse> => packetConnectionResponse(packets));
}

function packetConnectionResponse(
  packets: ReturnType<typeof packet>[],
  pageInfoOverrides: Partial<PageInfoPayload> = {}
): GraphQLResponse {
  return {
    data: {
      listWorkPackets: {
        edges: packets.map((node, index) => ({
          cursor: `cursor_${index + 1}`,
          node
        })),
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: packets.length > 0 ? "cursor_1" : null,
          endCursor: packets.length > 0 ? `cursor_${packets.length}` : null,
          ...pageInfoOverrides
        }
      }
    }
  };
}

function packet(overrides: Partial<PacketPayload> = {}) {
  return {
    __typename: "WorkPacket",
    id: "packet_1",
    title: "First packet",
    state: "active",
    currentVersionId: "version_1",
    operationId: "operation_1",
    updatedAt: "2026-07-09T12:00:00Z",
    ...overrides
  };
}

type PacketPayload = {
  id: string;
  title: string;
  state: string;
  currentVersionId: string | null;
  operationId: string | null;
  updatedAt: string;
};

type PageInfoPayload = {
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  startCursor: string | null;
  endCursor: string | null;
};
