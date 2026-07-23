import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createRelayEnvironment } from "../../relay/environment";
import * as support from "./routeTestSupport";

const rawErrorSentinel = "RAW_RUN_DETAIL_ERROR_SENTINEL_7f91c6";

describe("all-runs route recovery", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("retries list and detail reads independently with safe public copy", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let listAttempts = 0;
    let detailAttempts = 0;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        listAttempts += 1;
        if (listAttempts === 1) throw new Error(rawErrorSentinel);
        return support.runsConnectionResponse([support.runSummary()]);
      }

      if (request.name === "RunDetailQuery") {
        detailAttempts += 1;
        if (detailAttempts === 1) throw new Error(rawErrorSentinel);
        return { data: { operatorRunState: support.runState() } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    expect(await screen.findByText("Unable to load runs.")).toBeInTheDocument();
    expect(await screen.findByText("Selected run details are unavailable.")).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent(rawErrorSentinel);

    fireEvent.click(screen.getByRole("button", { name: "Retry runs" }));

    expect(
      await screen.findByRole("button", { name: /Review the newest authorized run/i }),
    ).toBeInTheDocument();
    expect(listAttempts).toBe(2);
    expect(detailAttempts).toBe(1);

    fireEvent.click(screen.getByRole("button", { name: "Retry run details" }));

    expect(await screen.findByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
    expect(listAttempts).toBe(2);
    expect(detailAttempts).toBe(2);
  });

  it("retains the current list page and selection when page continuation fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let continuationAttempts = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery" && variables.after === null) {
        return support.runsConnectionResponse([support.runSummary()], {
          endCursor: "run_page_cursor",
          hasNextPage: true,
        });
      }

      if (request.name === "RunsRouteQuery") {
        continuationAttempts += 1;
        if (continuationAttempts === 1) throw new Error(rawErrorSentinel);
        return support.runsConnectionResponse([
          support.runSummary({
            id: "run_next_page",
            objective: "Recovered next-page run",
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
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(await screen.findByText("Unable to load next run page.")).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent(rawErrorSentinel);
    expect(
      screen.getByRole("button", { name: /Review the newest authorized run/i }),
    ).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("heading", { name: "Newest packet" })).toBeInTheDocument();
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_new");

    fireEvent.click(screen.getByRole("button", { name: "Retry run page" }));

    expect(
      await screen.findByRole("button", { name: /Recovered next-page run/i }),
    ).toBeInTheDocument();
    expect(continuationAttempts).toBe(2);
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_new");
  });

  it.each([
    ["invalid", ""],
    ["missing", "run_missing"],
    ["forbidden", "run_forbidden"],
  ])(
    "retains a present %s URL selection and uses the same non-enumerating detail state",
    async (kind, runId) => {
      vi.spyOn(console, "error").mockImplementation(() => undefined);
      const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
        if (request.name === "RunsRouteQuery") {
          return support.runsConnectionResponse([support.runSummary()]);
        }

        if (request.name === "RunDetailQuery") {
          expect(variables.id).toBe(runId);
          if (kind === "forbidden") throw new Error(rawErrorSentinel);
          return { data: { operatorRunState: null } };
        }

        throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
      });

      const encodedSelection = runId ? `runId=${runId}` : "runId=";
      support.renderWithRelay(network, `/runs?${encodedSelection}`);

      expect(
        await screen.findByRole("button", { name: /Review the newest authorized run/i }),
      ).not.toHaveAttribute("aria-current");
      expect(await screen.findByText("Selected run details are unavailable.")).toBeInTheDocument();
      expect(document.body).not.toHaveTextContent(rawErrorSentinel);
      expect(screen.getByTestId("route-location")).toHaveTextContent(`/runs?${encodedSelection}`);
      expect(support.lastVariablesFor(network, "RunDetailQuery")).toMatchObject({ id: runId });
    },
  );

  it("retains a stale runId through the production Relay error path without enumeration", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
        const body = JSON.parse(String(init?.body)) as {
          query: string;
          variables: Record<string, unknown>;
        };

        if (body.query.includes("RunsRouteQuery")) {
          return Response.json(support.runsConnectionResponse([support.runSummary()]));
        }

        expect(body.query).toContain("RunDetailQuery");
        expect(body.variables.id).toBe("run_stale");

        return Response.json({
          data: { operatorRunState: null },
          errors: [
            {
              message: rawErrorSentinel,
              path: ["operatorRunState"],
              extensions: { code: "stale_run_state" },
            },
          ],
        });
      }),
    );

    support.renderWithRelayEnvironment(createRelayEnvironment(), "/runs?runId=run_stale");

    expect(
      await screen.findByRole("button", { name: /Review the newest authorized run/i }),
    ).not.toHaveAttribute("aria-current");
    expect(await screen.findByText("Selected run details are unavailable.")).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent(rawErrorSentinel);
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_stale");
    expect(screen.queryByRole("heading", { name: "Newest packet" })).not.toBeInTheDocument();
  });

  it("retains loaded activity after continuation failure and clears it with detail on selection", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const replacement = support.deferredGraphQLResponse();
    const secondRun = support.runSummary({
      id: "run_second",
      objective: "Second visible run",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "RunsRouteQuery") {
        return support.runsConnectionResponse([support.runSummary(), secondRun]);
      }

      if (request.name === "RunDetailQuery" && variables.id === "run_second") {
        return replacement.promise;
      }

      if (request.name === "RunDetailQuery" && variables.activityAfter !== null) {
        throw new Error(rawErrorSentinel);
      }

      if (request.name === "RunDetailQuery") {
        return { data: { operatorRunState: support.runState() } };
      }

      throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
    });

    support.renderWithRelay(network, "/runs?runId=run_new");

    const activity = await screen.findByRole("region", { name: "Run activity" });
    fireEvent.click(within(activity).getByRole("button", { name: "Load more activity" }));

    expect(await within(activity).findByText("Unable to load more activity.")).toBeInTheDocument();
    expect(within(activity).getByText("Release verification")).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent(rawErrorSentinel);

    fireEvent.click(screen.getByRole("button", { name: /Second visible run/i }));

    await waitFor(() => {
      expect(screen.queryByRole("heading", { name: "Newest packet" })).not.toBeInTheDocument();
      expect(screen.queryByRole("region", { name: "Run activity" })).not.toBeInTheDocument();
    });
    expect(screen.getByText("Loading selected run...")).toBeInTheDocument();
    expect(screen.getByTestId("route-location")).toHaveTextContent("/runs?runId=run_second");
  });
});
