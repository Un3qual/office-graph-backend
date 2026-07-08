import type { GraphQLResponse, RequestParameters, Variables } from "relay-runtime";

const GRAPHQL_FETCH_TIMEOUT_MS = 30_000;

export async function fetchGraphQL(
  request: RequestParameters,
  variables: Variables
): Promise<GraphQLResponse> {
  if (!request.text) {
    throw new Error(`Relay request "${request.name}" is missing compiled GraphQL text.`);
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), GRAPHQL_FETCH_TIMEOUT_MS);

  try {
    const response = await fetch("/graphql", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        accept: "application/json",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        query: request.text,
        variables
      }),
      signal: controller.signal
    });

    const payload = await readGraphQLResponse(response);

    if (!response.ok && payload) {
      return payload;
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
  }
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
