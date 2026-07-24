import { fireEvent, screen, within } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import * as support from "./routeTestSupport";

describe("all-runs route activity and command boundaries", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("appends the next activity page exactly once without reusing the run-list cursor", async () => {
    const firstState = support.runState();
    const nextState = support.runState({
      activity: {
        edges: [
          {
            cursor: "activity_cursor_3",
            node: {
              kind: "observation",
              stableId: "observation_3",
              title: "Later execution observation",
              status: "succeeded",
            },
          },
        ],
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: true,
          startCursor: "activity_cursor_3",
          endCursor: "activity_cursor_3",
        },
      },
    });
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        return support.runsConnectionResponse([support.runSummary()], {
          hasNextPage: true,
          endCursor: "run_list_cursor_1",
        });
      }

      if (request.name === "RunDetailQuery") {
        return { data: { operatorRunState: firstState } };
      }

      if (request.name === "RunActivityPageQuery") {
        return { data: { operatorRunState: { activity: nextState.activity } } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    const activity = await screen.findByRole("region", { name: "Run activity" });
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    fireEvent.click(within(activity).getByRole("button", { name: "Load more activity" }));

    expect(await within(activity).findByText("Later execution observation")).toBeInTheDocument();
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    expect(within(activity).getAllByText("Later execution observation")).toHaveLength(1);
    expect(
      network.mock.calls.filter(
        ([request, variables]) =>
          request.name === "RunActivityPageQuery" &&
          variables.activityAfter === "activity_cursor_2",
      ),
    ).toHaveLength(1);
    expect(support.lastVariablesFor(network, "RunActivityPageQuery")).toEqual({
      id: "run_new",
      activityFirst: 5,
      activityAfter: "activity_cursor_2",
    });
    expect(support.lastVariablesFor(network, "RunsRouteQuery")).toMatchObject({
      first: 50,
      after: null,
    });
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_new");
  });

  it("keeps loaded activity visible when continuation fails and retries only that page", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let continuationAttempts = 0;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        return support.runsConnectionResponse([support.runSummary()]);
      }

      if (request.name === "RunDetailQuery") {
        return { data: { operatorRunState: support.runState() } };
      }

      if (request.name === "RunActivityPageQuery") {
        continuationAttempts += 1;

        if (continuationAttempts === 1) {
          throw new Error("credential-bearing activity transport failure");
        }

        return {
          data: {
            operatorRunState: {
              activity: {
                edges: [
                  {
                    cursor: "activity_cursor_3",
                    node: {
                      kind: "observation",
                      stableId: "observation_3",
                      title: "Recovered execution observation",
                      status: "succeeded",
                    },
                  },
                ],
                pageInfo: {
                  hasNextPage: false,
                  hasPreviousPage: true,
                  startCursor: "activity_cursor_3",
                  endCursor: "activity_cursor_3",
                },
              },
            },
          },
        };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

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

  it("resets loaded activity pages when the selected run changes", async () => {
    const secondSummary = support.runSummary({
      id: "run_second",
      objective: "Second visible run",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        return support.runsConnectionResponse([support.runSummary(), secondSummary]);
      }

      if (request.name === "RunDetailQuery" && variables.id === "run_second") {
        return {
          data: {
            operatorRunState: support.runState({
              packet: {
                id: "packet_second",
                relayId: "d29ya19wYWNrZXQ6cGFja2V0X3NlY29uZA==",
                title: "Second packet",
                state: "active",
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
          },
        };
      }

      if (request.name === "RunActivityPageQuery") {
        return {
          data: {
            operatorRunState: {
              activity: {
                edges: [
                  {
                    cursor: "activity_cursor_3",
                    node: {
                      kind: "observation",
                      stableId: "observation_3",
                      title: "Later execution observation",
                      status: "succeeded",
                    },
                  },
                ],
                pageInfo: {
                  hasNextPage: false,
                  hasPreviousPage: true,
                  startCursor: "activity_cursor_3",
                  endCursor: "activity_cursor_3",
                },
              },
            },
          },
        };
      }

      if (request.name === "RunDetailQuery") {
        return { data: { operatorRunState: support.runState() } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    const activity = await screen.findByRole("region", { name: "Run activity" });
    fireEvent.click(within(activity).getByRole("button", { name: "Load more activity" }));
    expect(await within(activity).findByText("Later execution observation")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /Second visible run/i }));

    const replacementActivity = await screen.findByRole("region", { name: "Run activity" });
    expect(within(replacementActivity).getByText("Second run started")).toBeInTheDocument();
    expect(
      within(replacementActivity).queryByText("Later execution observation"),
    ).not.toBeInTheDocument();
    expect(support.lastVariablesFor(network, "RunDetailQuery")).toMatchObject({
      id: "run_second",
      activityAfter: null,
    });
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_second");
  });

  it("links packet history to the exact packet route without adding a command", async () => {
    support.renderWithRelay(support.createRunsNetwork(), "/runs?runId=run_new");

    expect(await screen.findByRole("link", { name: "Open packet history" })).toHaveAttribute(
      "href",
      "/packets?packetId=d29ya19wYWNrZXQ6MTIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDAw",
    );
    expect(
      screen.queryByRole("button", { name: /start|approve|verify|waive/i }),
    ).not.toBeInTheDocument();
  });
});
