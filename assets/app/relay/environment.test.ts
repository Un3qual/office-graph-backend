import { fetchQuery } from "react-relay";
import { afterEach, describe, expect, it, vi } from "vitest";
import PacketsRouteQuery from "./__generated__/PacketsRouteQuery.graphql";
import { createRelayEnvironment } from "./environment";
import { GraphQLResponseError } from "./fetchGraphQL";

const variables = {
  first: 50,
  after: null,
  createdOperationId: null,
  loadCreatedPacket: false,
  packetId: "not-a-relay-id",
  loadLinkedPacket: true,
};

describe("production Relay network", () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("lets the compiled packet catch recover a field error while preserving list data", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json({
          data: {
            operatorPacketCreateAffordance: {
              identity: "create_work_packet",
              state: "enabled",
            },
            listWorkPackets: packetConnection(),
            linkedPacket: null,
          },
          errors: [
            {
              message: "Could not decode ID value.",
              path: ["linkedPacket"],
            },
          ],
        }),
      ),
    );

    await expect(
      fetchQuery(createRelayEnvironment(), PacketsRouteQuery, variables).toPromise(),
    ).resolves.toMatchObject({
      linkedPacket: null,
      listWorkPackets: {
        edges: [{ node: { id: "relay_packet_1" } }],
      },
    });
  });

  it("rejects an uncaught packet-list field error through Relay", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json({
          data: {
            operatorPacketCreateAffordance: {
              identity: "create_work_packet",
              state: "enabled",
            },
            listWorkPackets: null,
            linkedPacket: null,
          },
          errors: [
            {
              message: "Packet list access is forbidden.",
              path: ["listWorkPackets"],
            },
          ],
        }),
      ),
    );

    const outcome = fetchQuery(createRelayEnvironment(), PacketsRouteQuery, variables).toPromise();

    await expect(outcome).rejects.toThrow(
      "Relay: Unexpected response payload - check server logs for details.",
    );
    await expect(outcome).rejects.not.toBeInstanceOf(GraphQLResponseError);
  });

  it.each([
    [
      "an HTTP failure",
      new Response("<html>server error</html>", { status: 503 }),
      'GraphQL request "PacketsRouteQuery" failed with status 503.',
    ],
    [
      "a non-JSON success response",
      new Response("not json", { status: 200 }),
      'GraphQL request "PacketsRouteQuery" returned an invalid JSON response.',
    ],
  ])("rejects %s before Relay normalization", async (_case, response, message) => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response));

    await expect(
      fetchQuery(createRelayEnvironment(), PacketsRouteQuery, variables).toPromise(),
    ).rejects.toThrow(message);
  });

  it("keeps the Relay request timeout as a network rejection", async () => {
    vi.useFakeTimers();
    vi.stubGlobal(
      "fetch",
      vi.fn((_path: string, init?: RequestInit) => {
        return new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => {
            reject(new DOMException("The operation was aborted.", "AbortError"));
          });
        });
      }),
    );

    const outcome = fetchQuery(createRelayEnvironment(), PacketsRouteQuery, variables)
      .toPromise()
      .then(
        () => "resolved",
        (error: unknown) => (error instanceof DOMException ? error.name : String(error)),
      );

    await vi.advanceTimersByTimeAsync(30_000);

    await expect(outcome).resolves.toContain("AbortError");
    expect(vi.getTimerCount()).toBe(0);
  });

  it("aborts the production Relay request on subscription disposal and ignores late data", async () => {
    let resolveRequest!: (response: Response) => void;
    let observedSignal: AbortSignal | undefined;
    vi.stubGlobal(
      "fetch",
      vi.fn((_path: string, init?: RequestInit) => {
        observedSignal = init?.signal ?? undefined;
        return new Promise<Response>((resolve) => {
          resolveRequest = resolve;
        });
      }),
    );
    const observer = {
      next: vi.fn(),
      error: vi.fn(),
      complete: vi.fn(),
    };
    const subscription = fetchQuery(
      createRelayEnvironment(),
      PacketsRouteQuery,
      variables,
    ).subscribe(observer);

    await vi.waitFor(() => expect(observedSignal).toBeDefined());
    subscription.unsubscribe();

    expect(observedSignal?.aborted).toBe(true);

    resolveRequest(
      Response.json({
        data: {
          operatorPacketCreateAffordance: {
            identity: "create_work_packet",
            state: "enabled",
          },
          listWorkPackets: packetConnection(),
          linkedPacket: null,
        },
      }),
    );
    await Promise.resolve();
    await Promise.resolve();

    expect(observer.next).not.toHaveBeenCalled();
    expect(observer.error).not.toHaveBeenCalled();
    expect(observer.complete).not.toHaveBeenCalled();
  });
});

function packetConnection() {
  return {
    edges: [
      {
        cursor: "cursor_1",
        node: {
          id: "relay_packet_1",
          title: "First packet",
          state: "ready",
          currentVersionId: "version_1",
          operationId: "operation_1",
          updatedAt: "2026-07-23T12:00:00Z",
        },
      },
    ],
    pageInfo: {
      hasNextPage: false,
      hasPreviousPage: false,
      startCursor: "cursor_1",
      endCursor: "cursor_1",
    },
  };
}
