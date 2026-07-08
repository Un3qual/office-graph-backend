import type { RequestParameters } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchGraphQL } from "./fetchGraphQL";

describe("fetchGraphQL", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("throws a status-aware error when an HTTP failure response is not JSON", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("<html>server error</html>", {
          status: 500,
          headers: { "content-type": "text/html" }
        })
      )
    );

    await expect(fetchGraphQL(request("BrokenQuery"), {})).rejects.toThrow(
      'GraphQL request "BrokenQuery" failed with status 500.'
    );
  });

  it("returns GraphQL error payloads even when the HTTP status is not ok", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json(
          {
            errors: [{ message: "Validation failed" }]
          },
          { status: 400 }
        )
      )
    );

    await expect(fetchGraphQL(request("ValidationQuery"), {})).resolves.toEqual({
      errors: [{ message: "Validation failed" }]
    });
  });
});

function request(name: string): RequestParameters {
  return {
    cacheID: name,
    id: null,
    name,
    operationKind: "query",
    text: `query ${name} { ok }`,
    metadata: {}
  };
}
