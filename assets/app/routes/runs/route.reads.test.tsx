import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { describe, expect, it, vi } from "vitest";
import * as support from "./routeTestSupport";

describe("all-runs route reads", () => {
  it("renders a run-specific empty state without loading detail", async () => {
    const network = support.createRunsNetwork({ rows: [] });

    support.renderWithRelay(network);

    expect(await screen.findByText("No runs are available.")).toBeInTheDocument();
    expect(network.mock.calls.some(([request]) => request.name === "RunDetailQuery")).toBe(false);
    expect(screen.getByRole("region", { name: "Run detail" })).toHaveTextContent(
      "Select a run to inspect its current state.",
    );
  });

  it("loads explicit detail independently when the initial list fails and retries only the list", async () => {
    let listAttempts = 0;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        listAttempts += 1;

        if (listAttempts === 1) {
          throw new Error("credential-bearing list transport failure");
        }

        return support.runsConnectionResponse([support.runSummary()]);
      }

      if (request.name === "RunDetailQuery") {
        return { data: { operatorRunState: support.runState() } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    expect(await screen.findByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
    expect(await screen.findByText("Unable to load runs.")).toBeInTheDocument();
    expect(screen.queryByText(/credential-bearing/i)).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Retry runs" }));

    expect(
      await screen.findByRole("button", { name: /Review the newest authorized run/i }),
    ).toBeInTheDocument();
    expect(listAttempts).toBe(2);
    expect(
      network.mock.calls.filter(([request]) => request.name === "RunDetailQuery"),
    ).toHaveLength(1);
  });

  it("keeps the list visible when detail fails and retries only the selected detail", async () => {
    let detailAttempts = 0;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        return support.runsConnectionResponse([support.runSummary()]);
      }

      if (request.name === "RunDetailQuery") {
        detailAttempts += 1;

        if (detailAttempts === 1) {
          throw new Error("raw detail authorization failure");
        }

        return { data: { operatorRunState: support.runState() } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    expect(
      await screen.findByRole("button", { name: /Review the newest authorized run/i }),
    ).toBeInTheDocument();
    expect(await screen.findByText("Selected run details are unavailable.")).toBeInTheDocument();
    expect(screen.queryByText(/raw detail authorization/i)).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Retry run details" }));

    expect(await screen.findByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
    expect(detailAttempts).toBe(2);
    expect(
      network.mock.calls.filter(([request]) => request.name === "RunsRouteQuery"),
    ).toHaveLength(1);
  });

  it("retains an unavailable explicit run id and renders the safe detail error", async () => {
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        return support.runsConnectionResponse([support.runSummary()]);
      }

      if (request.name === "RunDetailQuery") {
        return { data: { operatorRunState: null } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_unavailable");

    expect(
      await screen.findByRole("button", { name: /Review the newest authorized run/i }),
    ).toBeInTheDocument();
    expect(await screen.findByText("Selected run details are unavailable.")).toBeInTheDocument();
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_unavailable");
  });

  it("renders the server's newest-first rows and lifecycle labels", async () => {
    const older = support.runSummary({
      id: "run_old",
      objective: "Older authorized run",
      aggregateState: "blocked",
      executionState: "failed",
      verificationState: "unverified",
      insertedAt: "2026-07-22T19:00:00Z",
    });
    const network = support.createRunsNetwork({
      rows: [support.runSummary(), older],
    });

    support.renderWithRelay(network);

    const rows = await screen.findAllByRole("button", { name: /authorized run/i });
    expect(rows).toHaveLength(2);
    expect(rows[0]).toHaveTextContent("Review the newest authorized run");
    expect(rows[0]).toHaveTextContent("Running");
    expect(rows[0]).toHaveTextContent("Completed");
    expect(rows[0]).toHaveTextContent("Pending");
    expect(rows[1]).toHaveTextContent("Older authorized run");
    expect(rows[1]).toHaveTextContent("Blocked");
    expect(rows[1]).toHaveTextContent("Failed");
    expect(rows[1]).toHaveTextContent("Unverified");
  });

  it("selects the first visible run and writes it to the URL only when runId is absent", async () => {
    const network = support.createRunsNetwork();

    support.renderWithRelay(network);

    await waitFor(() => {
      expect(support.lastVariablesFor(network, "RunDetailQuery")).toEqual({
        id: "run_new",
        activityFirst: 5,
        activityAfter: null,
      });
    });
    await waitFor(() => {
      expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_new");
    });
    expect(
      screen.getByRole("button", { name: /Review the newest authorized run/i }),
    ).toHaveAttribute("aria-current", "true");
  });

  it("preserves an explicit visible URL selection", async () => {
    const selected = support.runSummary({
      id: "run_selected",
      objective: "Explicitly selected run",
    });
    const network = support.createRunsNetwork({
      rows: [support.runSummary(), selected],
      states: {
        run_selected: support.runState({
          run: {
            id: "run_selected",
            aggregateState: "verified",
            executionState: "completed",
            verificationState: "verified",
          },
        }),
      },
    });

    support.renderWithRelay(network, "/runs?runId=run_selected");

    await waitFor(() => {
      expect(support.lastVariablesFor(network, "RunDetailQuery")).toMatchObject({
        id: "run_selected",
      });
    });
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_selected");
    expect(await screen.findByRole("button", { name: /Explicitly selected run/i })).toHaveAttribute(
      "aria-current",
      "true",
    );
    expect(
      screen.getByRole("button", {
        name: /Review the newest authorized run/i,
      }),
    ).not.toHaveAttribute("aria-current");
  });

  it("loads authoritative detail for an explicit run id outside the current list page", async () => {
    const network = support.createRunsNetwork({
      states: {
        run_off_page: support.runState({
          packet: {
            id: "packet_off_page",
            relayId: "d29ya19wYWNrZXQ6cGFja2V0X29mZl9wYWdl",
            title: "Off-page packet",
            state: "active",
          },
          run: {
            id: "run_off_page",
            aggregateState: "running",
            executionState: "running",
            verificationState: "pending",
          },
        }),
      },
    });

    support.renderWithRelay(network, "/runs?runId=run_off_page");

    expect(await screen.findByRole("heading", { name: "Off-page packet" })).toBeInTheDocument();
    expect(support.lastVariablesFor(network, "RunDetailQuery")).toMatchObject({
      id: "run_off_page",
    });
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_off_page");
    expect(
      screen.getByRole("button", { name: /Review the newest authorized run/i }),
    ).not.toHaveAttribute("aria-current");
  });

  it("updates the URL after row selection", async () => {
    const second = support.runSummary({
      id: "run_second",
      objective: "Second visible run",
    });
    const network = support.createRunsNetwork({
      rows: [support.runSummary(), second],
      states: {
        run_second: support.runState({
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
        }),
      },
    });

    support.renderWithRelay(network);

    await waitFor(() => {
      expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_new");
    });
    fireEvent.click(await screen.findByRole("button", { name: /Second visible run/i }));

    await waitFor(() => {
      expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_second");
      expect(support.lastVariablesFor(network, "RunDetailQuery")).toMatchObject({
        id: "run_second",
      });
    });
  });

  it("retains the loaded page and selected detail while the next list page loads", async () => {
    const nextPage = support.deferredGraphQLResponse();
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        return variables.after
          ? nextPage.promise
          : support.runsConnectionResponse([support.runSummary()], {
              endCursor: "cursor_next",
              hasNextPage: true,
            });
      }

      if (request.name === "RunDetailQuery") {
        return { data: { operatorRunState: support.runState() } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    expect(await screen.findByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
    fireEvent.click(await screen.findByRole("button", { name: "Next" }));

    expect(screen.getByText("Loading next run page...")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /Review the newest authorized run/i }),
    ).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Newest packet" })).toBeInTheDocument();

    nextPage.resolve(
      support.runsConnectionResponse([
        support.runSummary({
          id: "run_second_page",
          objective: "Second page run",
        }),
      ]),
    );

    expect(await screen.findByRole("button", { name: /Second page run/i })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_new");
  });

  it("retains the loaded page and selected detail when next-page loading fails and retries paging", async () => {
    let pageAttempts = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        if (!variables.after) {
          return support.runsConnectionResponse([support.runSummary()], {
            endCursor: "cursor_next",
            hasNextPage: true,
          });
        }

        pageAttempts += 1;

        if (pageAttempts === 1) {
          throw new Error("raw paging transport failure");
        }

        return support.runsConnectionResponse([
          support.runSummary({
            id: "run_retried_page",
            objective: "Retried page run",
          }),
        ]);
      }

      if (request.name === "RunDetailQuery") {
        return { data: { operatorRunState: support.runState() } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    expect(await screen.findByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
    fireEvent.click(await screen.findByRole("button", { name: "Next" }));

    expect(await screen.findByText("Unable to load next run page.")).toBeInTheDocument();
    expect(screen.queryByText(/raw paging transport/i)).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /Review the newest authorized run/i }),
    ).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Newest packet" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Retry run page" }));

    expect(await screen.findByRole("button", { name: /Retried page run/i })).toBeInTheDocument();
    expect(pageAttempts).toBe(2);
    expect(screen.getByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
  });

  it("clears stale detail while replacement detail suspends", async () => {
    const replacement = support.deferredGraphQLResponse();
    const second = support.runSummary({
      id: "run_second",
      objective: "Second visible run",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        return support.runsConnectionResponse([support.runSummary(), second]);
      }

      if (request.name === "RunDetailQuery") {
        return variables.id === "run_second"
          ? replacement.promise
          : { data: { operatorRunState: support.runState() } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    expect(await screen.findByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Second visible run/i }));

    await waitFor(() => {
      expect(screen.queryByRole("heading", { name: "Newest packet" })).not.toBeInTheDocument();
    });
    expect(screen.getByText("Loading selected run...")).toBeInTheDocument();

    replacement.resolve({
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
        }),
      },
    });

    expect(await screen.findByRole("heading", { name: "Second packet" })).toBeInTheDocument();
  });

  it("renders packet, packet-version, checks, evidence, missing evidence, and verification state", async () => {
    support.renderWithRelay(support.createRunsNetwork());

    await screen.findByRole("heading", { name: "Newest packet" });
    const detail = screen.getByRole("region", { name: "Run detail" });

    expect(detail).toHaveTextContent("Newest packet");
    expect(detail).toHaveTextContent("Version 3");
    expect(detail).toHaveTextContent("Review the newest authorized run");
    expect(detail).toHaveTextContent("check_1");
    expect(detail).toHaveTextContent("Open");
    expect(detail).toHaveTextContent("Release evidence is ready.");
    expect(detail).toHaveTextContent("evidence_1");
    expect(detail).toHaveTextContent("Accepted");
    expect(detail).toHaveTextContent("check_2");
    expect(detail).toHaveTextContent("Missing accepted evidence");
    expect(detail).toHaveTextContent("Passed");
    expect(detail).toHaveTextContent("Owner acceptance");
  });

  it("renders the first bounded activity page without requesting a continuation", async () => {
    const network = support.createRunsNetwork();

    support.renderWithRelay(network);

    const activity = await screen.findByRole("region", { name: "Run activity" });
    expect(within(activity).getByText(/Release verification/)).toBeInTheDocument();
    expect(within(activity).getByText(/Accepted release evidence/)).toBeInTheDocument();
    expect(support.lastVariablesFor(network, "RunDetailQuery")).toMatchObject({
      activityFirst: 5,
      activityAfter: null,
    });
    expect(screen.getByRole("button", { name: "Load more activity" })).toBeInTheDocument();
    expect(
      network.mock.calls.filter(([request]) => request.name === "RunDetailQuery"),
    ).toHaveLength(1);
  });

  it("links to the operator workspace while preserving the selected run id", async () => {
    support.renderWithRelay(support.createRunsNetwork(), "/runs?runId=run_new");

    const link = await screen.findByRole("link", {
      name: "Open run in Operator",
    });
    expect(link).toHaveAttribute("href", "/operator?runId=run_new");
  });
});
