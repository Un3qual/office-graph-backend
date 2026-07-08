import type { GraphQLResponse, RequestParameters, Variables } from "relay-runtime";

export async function fetchGraphQL(
  request: RequestParameters,
  variables: Variables
): Promise<GraphQLResponse> {
  if (!request.text) {
    throw new Error(`Relay request "${request.name}" is missing compiled GraphQL text.`);
  }

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
    })
  });

  const payload = (await response.json()) as GraphQLResponse;

  if (!response.ok) {
    throw new Error(`GraphQL request "${request.name}" failed with status ${response.status}.`);
  }

  return payload;
}
