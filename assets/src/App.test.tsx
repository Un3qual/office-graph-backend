import { render, screen } from "@testing-library/react";
import {
  Environment,
  Network,
  RecordSource,
  Store,
  type FetchFunction,
  type GraphQLResponse
} from "relay-runtime";
import { describe, expect, it } from "vitest";
import { getOfficeGraphDataID } from "../app/relay/environment";
import { App } from "./App";

describe("operator console app shell", () => {
  it("renders the primary workbench regions", async () => {
    render(<App relayEnvironment={createRelayTestEnvironment(emptyOperatorNetwork)} />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Operator Console" })
    ).toBeInTheDocument();
    expect(screen.getByRole("navigation", { name: "Operator sections" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Inbox" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Item detail" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Run State" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Verification" })).toBeInTheDocument();
    expect(await screen.findByText("No operator workflow items.")).toBeInTheDocument();
  });
});

function createRelayTestEnvironment(fetch: FetchFunction) {
  return new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(fetch),
    store: new Store(new RecordSource())
  });
}

const emptyOperatorNetwork: FetchFunction = async (request): Promise<GraphQLResponse> => {
  if (request.name === "OperatorWorkflowRouteQuery") {
    return {
      data: {
        operatorWorkflowItems: {
          edges: [],
          pageInfo: {
            hasNextPage: false,
            hasPreviousPage: false,
            startCursor: null,
            endCursor: null
          }
        }
      }
    };
  }

  throw new Error(`Unexpected Relay request in app-shell test: ${request.name}`);
};
