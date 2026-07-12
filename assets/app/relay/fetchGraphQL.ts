import {
  Observable,
  type GraphQLResponse,
  type RequestParameters,
  type Variables,
} from "relay-runtime";

const GRAPHQL_FETCH_TIMEOUT_MS = 30_000;

export class GraphQLResponseError extends Error {
  readonly source: GraphQLResponse;
  readonly status: number;
  readonly requestName: string;

  constructor(message: string, source: GraphQLResponse, status: number, requestName: string) {
    super(message);
    this.name = "GraphQLResponseError";
    this.source = source;
    this.status = status;
    this.requestName = requestName;
  }
}

export async function fetchGraphQL(
  request: RequestParameters,
  variables: Variables,
): Promise<GraphQLResponse> {
  return fetchGraphQLWithSignal(request, variables);
}

async function fetchGraphQLWithSignal(
  request: RequestParameters,
  variables: Variables,
  disposalSignal?: AbortSignal,
): Promise<GraphQLResponse> {
  if (!request.text) {
    throw new Error(`Relay request "${request.name}" is missing compiled GraphQL text.`);
  }

  const controller = new AbortController();
  const abortDisposedRequest = () => controller.abort(disposalSignal?.reason);
  disposalSignal?.addEventListener("abort", abortDisposedRequest, { once: true });
  if (disposalSignal?.aborted) abortDisposedRequest();
  const timeoutId = setTimeout(() => controller.abort(), GRAPHQL_FETCH_TIMEOUT_MS);

  try {
    const response = await fetch("/graphql", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        query: request.text,
        variables,
      }),
      signal: controller.signal,
    });

    const payload = await readGraphQLResponse(response);

    if (payload) {
      const firstError = "errors" in payload ? payload.errors?.[0] : null;

      if (firstError) {
        throw new GraphQLResponseError(firstError.message, payload, response.status, request.name);
      }
    }

    if (!response.ok) {
      throw new Error(`GraphQL request "${request.name}" failed with status ${response.status}.`);
    }

    if (!payload) {
      throw new Error(`GraphQL request "${request.name}" returned an invalid JSON response.`);
    }

    return payload;
  } finally {
    clearTimeout(timeoutId);
    disposalSignal?.removeEventListener("abort", abortDisposedRequest);
  }
}

export function executeGraphQL(request: RequestParameters, variables: Variables) {
  return Observable.create<GraphQLResponse>((sink) => {
    const controller = new AbortController();
    let disposed = false;

    void fetchGraphQLWithSignal(request, variables, controller.signal).then(
      (payload) => {
        if (disposed) return;
        sink.next(payload);
        sink.complete();
      },
      (error: unknown) => {
        if (!disposed) sink.error(error instanceof Error ? error : new Error(String(error)));
      },
    );

    return () => {
      disposed = true;
      controller.abort();
    };
  });
}

async function readGraphQLResponse(response: Response): Promise<GraphQLResponse | null> {
  const body = await response.text();

  if (body.trim() === "") {
    return null;
  }

  try {
    const payload = JSON.parse(body) as unknown;
    return isGraphQLResponse(payload) ? payload : null;
  } catch {
    return null;
  }
}

function isGraphQLResponse(payload: unknown): payload is GraphQLResponse {
  return (
    typeof payload === "object" &&
    payload !== null &&
    !Array.isArray(payload) &&
    ("data" in payload || "errors" in payload)
  );
}
