import type { GraphQLResponse, RequestParameters } from "relay-runtime";
import { describe, expect, it } from "vitest";
import { createNetworkMock } from "./routeTestSupport";

const request = {
  cacheID: "runs-route-test",
  id: null,
  metadata: {},
  name: "RunsRouteQuery",
  operationKind: "query",
  text: null,
} satisfies RequestParameters;

describe("runs route network test support", () => {
  it("invokes the resolver synchronously while returning its response as a promise", async () => {
    const response: GraphQLResponse = { data: { viewer: null } };
    let invoked = false;
    const network = createNetworkMock(() => {
      invoked = true;
      return response;
    });

    const outcome = network(request, {});

    expect(invoked).toBe(true);
    await expect(outcome).resolves.toBe(response);
  });

  it("converts synchronous resolver failures into rejected network responses", async () => {
    const failure = new Error("transport failed");
    const network = createNetworkMock((): GraphQLResponse => {
      throw failure;
    });

    await expect(network(request, {})).rejects.toBe(failure);
  });
});
