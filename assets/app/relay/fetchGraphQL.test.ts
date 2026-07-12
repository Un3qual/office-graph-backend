import type { RequestParameters } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import { executeGraphQL, fetchGraphQL, GraphQLResponseError } from "./fetchGraphQL";

describe("fetchGraphQL", () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("returns GraphQL data for successful responses", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      Response.json({
        data: { ok: true },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(fetchGraphQL(request("HappyQuery"), { id: "ok" })).resolves.toEqual({
      data: { ok: true },
    });
    expect(fetchMock).toHaveBeenCalledWith(
      "/graphql",
      expect.objectContaining({
        method: "POST",
        credentials: "same-origin",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
        },
        signal: expect.any(AbortSignal),
      }),
    );

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(JSON.parse(init.body as string)).toEqual({
      query: "query HappyQuery { ok }",
      variables: { id: "ok" },
    });
  });

  it("requires compiled GraphQL text", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const missingText = {
      ...request("MissingText"),
      text: null,
    };

    await expect(fetchGraphQL(missingText, {})).rejects.toThrow(
      'Relay request "MissingText" is missing compiled GraphQL text.',
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("throws a status-aware error when an HTTP failure response is not JSON", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("<html>server error</html>", {
          status: 500,
          headers: { "content-type": "text/html" },
        }),
      ),
    );

    await expect(fetchGraphQL(request("BrokenQuery"), {})).rejects.toThrow(
      'GraphQL request "BrokenQuery" failed with status 500.',
    );
  });

  it("throws GraphQL response errors with extensions even when the HTTP status is not ok", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json(
          {
            errors: [
              {
                message: "Validation failed",
                extensions: { code: "source_graph_item_check_mismatch" },
              },
            ],
          },
          { status: 400 },
        ),
      ),
    );

    await expect(fetchGraphQL(request("ValidationQuery"), {})).rejects.toMatchObject({
      message: "Validation failed",
      requestName: "ValidationQuery",
      status: 400,
      source: {
        errors: [
          {
            message: "Validation failed",
            extensions: { code: "source_graph_item_check_mismatch" },
          },
        ],
      },
    });
  });

  it("throws GraphQL errors returned with partial data", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json({
          data: { operatorWorkflowItems: null },
          errors: [{ message: "Operator workflow access is forbidden" }],
        }),
      ),
    );

    try {
      await fetchGraphQL(request("OperatorWorkflowRouteQuery"), {});
      throw new Error("Expected GraphQLResponseError");
    } catch (error) {
      expect(error).toBeInstanceOf(GraphQLResponseError);
      expect(error).toMatchObject({
        message: "Operator workflow access is forbidden",
        source: {
          data: { operatorWorkflowItems: null },
          errors: [{ message: "Operator workflow access is forbidden" }],
        },
      });
    }
  });

  it("throws when a successful response body is empty", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("", { status: 200 })));

    await expect(fetchGraphQL(request("EmptyQuery"), {})).rejects.toThrow(
      'GraphQL request "EmptyQuery" returned an invalid JSON response.',
    );
  });

  it("throws when a successful response body is invalid JSON", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("not json", { status: 200 })));

    await expect(fetchGraphQL(request("InvalidJsonQuery"), {})).rejects.toThrow(
      'GraphQL request "InvalidJsonQuery" returned an invalid JSON response.',
    );
  });

  it("throws when a successful response is valid JSON but not a GraphQL response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ ok: true })));

    await expect(fetchGraphQL(request("ShapeQuery"), {})).rejects.toThrow(
      'GraphQL request "ShapeQuery" returned an invalid JSON response.',
    );
  });

  it("aborts GraphQL requests that exceed the request timeout", async () => {
    vi.useFakeTimers();

    const fetchMock = vi.fn((_path: string, init?: RequestInit) => {
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          reject(new DOMException("The operation was aborted.", "AbortError"));
        });
      });
    });

    vi.stubGlobal("fetch", fetchMock);

    const result = fetchGraphQL(request("SlowQuery"), {});
    const outcome = result.then(
      () => "resolved",
      (error: unknown) => (error instanceof DOMException ? error.name : String(error)),
    );

    await vi.advanceTimersByTimeAsync(30_000);

    await expect(outcome).resolves.toBe("AbortError");
    expect(fetchMock).toHaveBeenCalledWith(
      "/graphql",
      expect.objectContaining({
        signal: expect.any(AbortSignal),
      }),
    );
    expect(vi.getTimerCount()).toBe(0);
  });

  it("aborts the underlying request on subscription disposal and ignores a late payload", async () => {
    let resolveRequest!: (response: Response) => void;
    let observedSignal: AbortSignal | undefined;
    const fetchMock = vi.fn((_path: string, init?: RequestInit) => {
      observedSignal = init?.signal ?? undefined;
      return new Promise<Response>((resolve) => {
        resolveRequest = resolve;
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const observer = {
      next: vi.fn(),
      error: vi.fn(),
      complete: vi.fn(),
    };
    const subscription = executeGraphQL(request("DisposedQuery"), {}).subscribe(observer);

    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledOnce());
    subscription.unsubscribe();

    expect(observedSignal?.aborted).toBe(true);

    resolveRequest(Response.json({ data: { late: true } }));
    await Promise.resolve();
    await Promise.resolve();

    expect(observer.next).not.toHaveBeenCalled();
    expect(observer.error).not.toHaveBeenCalled();
    expect(observer.complete).not.toHaveBeenCalled();
  });
});

function request(name: string): RequestParameters {
  return {
    cacheID: name,
    id: null,
    name,
    operationKind: "query",
    text: `query ${name} { ok }`,
    metadata: {},
  };
}
