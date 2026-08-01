import { fireEvent, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  activityPageResponse,
  createNetworkMock,
  createRunsNetwork,
  lastVariablesFor,
  renderWithRelay,
  runDetailResponse,
  runPath,
  runRelayId,
  runState,
  runSummary,
  runsConnectionResponse,
} from "./routeTestSupport";

describe("all-runs route activity and command boundaries", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("appends the next activity page exactly once without reusing the run-list cursor", async () => {
    const firstState = runState();
    const network = createNetworkMock((request) => {
      if (request.name === "RunsRouteQuery") {
        return runsConnectionResponse([runSummary()], {
          hasNextPage: true,
          endCursor: "run_list_cursor_1",
        });
      }

      if (request.name === "RunDetailQuery") {
        return runDetailResponse(firstState);
      }

      if (request.name === "RunActivityPaginationQuery") {
        return activityPageResponse({ title: "Later execution observation" });
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    renderWithRelay(network, "/runs?runId=run_new");

    const activity = await screen.findByRole("region", { name: "Run activity" });
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    fireEvent.click(within(activity).getByRole("button", { name: "Load more activity" }));

    expect(await within(activity).findByText("Later execution observation")).toBeInTheDocument();
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    expect(within(activity).getAllByText("Later execution observation")).toHaveLength(1);
    expect(
      network.mock.calls.filter(([request]) => request.name === "RunActivityPaginationQuery"),
    ).toHaveLength(1);
    expect(lastVariablesFor(network, "RunActivityPaginationQuery")).toEqual({
      id: "run_new",
      first: 5,
      after: "activity_cursor_2",
    });
    expect(lastVariablesFor(network, "RunsRouteQuery")).toMatchObject({
      first: 50,
      after: null,
    });
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_new");
  });

  it("keeps loaded activity visible when continuation fails and retries only that page", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let continuationAttempts = 0;
    const network = createNetworkMock((request) => {
      if (request.name === "RunsRouteQuery") {
        return runsConnectionResponse([runSummary()]);
      }

      if (request.name === "RunDetailQuery") {
        return runDetailResponse();
      }

      if (request.name === "RunActivityPaginationQuery") {
        continuationAttempts += 1;

        if (continuationAttempts === 1) {
          throw new Error("credential-bearing activity transport failure");
        }

        return activityPageResponse({ title: "Recovered execution observation" });
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    renderWithRelay(network, "/runs?runId=run_new");

    const activity = await screen.findByRole("region", { name: "Run activity" });
    fireEvent.click(within(activity).getByRole("button", { name: "Load more activity" }));

    expect(await within(activity).findByRole("alert")).toHaveTextContent(
      "Unable to load more activity.",
    );
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    expect(within(activity).queryByText(/credential-bearing/i)).not.toBeInTheDocument();
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_new");

    fireEvent.click(within(activity).getByRole("button", { name: "Retry activity" }));

    expect(
      await within(activity).findByText("Recovered execution observation"),
    ).toBeInTheDocument();
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    expect(continuationAttempts).toBe(2);
    expect(
      network.mock.calls.filter(([request]) => request.name === "RunsRouteQuery"),
    ).toHaveLength(1);
  });

  it("keeps GraphQL field errors inside the activity retry boundary", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let continuationAttempts = 0;
    let detailAttempts = 0;
    const rawErrorSentinel = "RAW_ACTIVITY_FIELD_ERROR_SENTINEL_63a8";
    const network = createNetworkMock((request, _variables) => {
      if (request.name === "RunsRouteQuery") {
        return runsConnectionResponse([runSummary()]);
      }

      if (request.name === "RunDetailQuery") {
        detailAttempts += 1;
        return runDetailResponse();
      }

      if (request.name === "RunActivityPaginationQuery") {
        continuationAttempts += 1;

        if (continuationAttempts === 1) {
          return {
            data: {
              operatorRunState: {
                activity: null,
              },
            },
            errors: [
              {
                message: rawErrorSentinel,
                path: ["operatorRunState", "activity"],
              },
            ],
          };
        }

        return activityPageResponse({ title: "Recovered field-error observation" });
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    renderWithRelay(network, "/runs?runId=run_new");

    const activity = await screen.findByRole("region", { name: "Run activity" });
    fireEvent.click(within(activity).getByRole("button", { name: "Load more activity" }));

    expect(await within(activity).findByRole("alert")).toHaveTextContent(
      "Unable to load more activity.",
    );
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    expect(screen.queryByText("Selected run details are unavailable.")).not.toBeInTheDocument();
    expect(document.body).not.toHaveTextContent(rawErrorSentinel);

    fireEvent.click(within(activity).getByRole("button", { name: "Retry activity" }));

    expect(
      await within(activity).findByText("Recovered field-error observation"),
    ).toBeInTheDocument();
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    expect(continuationAttempts).toBe(2);
    expect(detailAttempts).toBe(1);
    expect(
      network.mock.calls
        .filter(([request]) => request.name === "RunActivityPaginationQuery")
        .map(([, variables]) => variables),
    ).toEqual([
      { id: "run_new", first: 5, after: "activity_cursor_2" },
      { id: "run_new", first: 5, after: "activity_cursor_2" },
    ]);
  });

  it("resets loaded activity pages when the selected run changes", async () => {
    const secondSummary = runSummary({
      id: "run_second",
      objective: "Second visible run",
    });
    const network = createNetworkMock((request, variables) => {
      if (request.name === "RunsRouteQuery") {
        return runsConnectionResponse([runSummary(), secondSummary]);
      }

      if (request.name === "RunDetailQuery" && variables.id === runRelayId("run_second")) {
        return runDetailResponse(
          runState({
            packet: {
              id: "packet_second",
              relayId: "d29ya19wYWNrZXQ6cGFja2V0X3NlY29uZA==",
              title: "Second packet",
            },
            run: {
              id: "run_second",
              aggregateState: "running",
              executionState: "running",
              verificationState: "pending",
            },
            activity: {
              edges: [
                {
                  cursor: "second_activity_cursor_1",
                  node: {
                    __typename: "OperatorRunActivity",
                    kind: "run",
                    stableId: "run_second",
                    title: "Second run started",
                    status: "running",
                  },
                },
              ],
              pageInfo: {
                hasNextPage: false,
                hasPreviousPage: false,
                startCursor: "second_activity_cursor_1",
                endCursor: "second_activity_cursor_1",
              },
            },
          }),
        );
      }

      if (request.name === "RunActivityPaginationQuery") {
        return activityPageResponse({ title: "Later execution observation" });
      }

      if (request.name === "RunDetailQuery") {
        return runDetailResponse();
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    renderWithRelay(network, "/runs?runId=run_new");

    const activity = await screen.findByRole("region", { name: "Run activity" });
    fireEvent.click(within(activity).getByRole("button", { name: "Load more activity" }));
    expect(await within(activity).findByText("Later execution observation")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /Second visible run/i }));

    const replacementActivity = await screen.findByRole("region", { name: "Run activity" });
    expect(within(replacementActivity).getByText("Second run started")).toBeInTheDocument();
    expect(
      within(replacementActivity).queryByText("Later execution observation"),
    ).not.toBeInTheDocument();
    expect(lastVariablesFor(network, "RunDetailQuery")).toMatchObject({
      id: runRelayId("run_second"),
    });
    expect(screen.getByTestId("route-location")).toHaveTextContent(runPath("run_second"));
  });

  it("links packet history to the exact packet route without adding a command", async () => {
    renderWithRelay(createRunsNetwork(), "/runs?runId=run_new");

    expect(await screen.findByRole("link", { name: "Open packet history" })).toHaveAttribute(
      "href",
      "/packets?packetId=d29ya19wYWNrZXQ6MTIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDAw",
    );
    expect(
      screen.queryByRole("button", { name: /start|approve|verify|waive/i }),
    ).not.toBeInTheDocument();
  });
});
