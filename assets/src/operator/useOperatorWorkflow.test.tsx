import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen, waitFor } from "@testing-library/react";
import { useEffect } from "react";
import type { ReactElement } from "react";
import { describe, expect, it, vi } from "vitest";
import { createGraphQLTestFetcher, graphQLInbox } from "./testSupport";
import { useOperatorWorkflow } from "./useOperatorWorkflow";
import type { GraphQLRequest } from "./workflowTypes";

describe("useOperatorWorkflow", () => {
  it("keeps an explicitly selected out-of-inbox item selected", async () => {
    const externalItem = {
      ...graphQLInbox.rows[0],
      normalizedEventId: "evt_external",
      typedId: { type: "normalized_intake_event", id: "evt_external" },
      graphLinks: []
    };
    const fetcher = createGraphQLTestFetcher({
      operatorInbox: graphQLInbox,
      operatorWorkflowItem: externalItem
    });

    renderWithQueryClient(<WorkflowProbe fetchGraphQL={fetcher} />);

    await waitFor(() => {
      expect(screen.getByTestId("selected-id")).toHaveTextContent("evt_1");
    });

    act(() => {
      screen.getByRole("button", { name: "Select external" }).click();
    });

    await waitFor(() => {
      expect(screen.getByTestId("selected-id")).toHaveTextContent("evt_external");
    });
  });

  it("clears a selected item when the inbox page becomes empty", async () => {
    const fetcher = createGraphQLTestFetcher({
      operatorInbox: { ...graphQLInbox, empty: true, rows: [] }
    });

    renderWithQueryClient(<WorkflowProbe fetchGraphQL={fetcher} initialSelectedId="evt_stale" />);

    await waitFor(() => {
      expect(screen.getByTestId("selected-id")).toHaveTextContent("none");
    });
  });

  it("resets inbox selections that disappear from the current page", async () => {
    const nextRow = {
      ...graphQLInbox.rows[0],
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" }
    };
    const fetcher = createGraphQLTestFetcher({
      operatorInbox: { ...graphQLInbox, rows: [nextRow] }
    });

    renderWithQueryClient(
      <WorkflowProbe fetchGraphQL={fetcher} initialInboxSelectedId="evt_stale" />
    );

    await waitFor(() => {
      expect(screen.getByTestId("selected-id")).toHaveTextContent("evt_2");
    });
  });

  it("loads the next inbox page through GraphQL cursor variables", async () => {
    const nextRow = {
      ...graphQLInbox.rows[0],
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" }
    };
    const fetcher = vi.fn(async ({ query, variables }: GraphQLRequest) => {
      if (query.includes("operatorInbox")) {
        return {
          data: {
            operatorInbox:
              variables.afterCursor === "cursor_1"
                ? {
                    ...graphQLInbox,
                    hasMore: false,
                    nextCursor: null,
                    afterCursor: "cursor_1",
                    rows: [nextRow]
                  }
                : { ...graphQLInbox, hasMore: true, nextCursor: "cursor_1", afterCursor: null }
          }
        };
      }

      return {
        data: {
          operatorPacketReadiness: {
            type: "packet_readiness",
            ready: true,
            status: "packet_ready",
            allowedNextActions: [],
            blockerReasons: [],
            sourceLinks: [],
            requiredChecks: [],
            sourceWatermark: null
          }
        }
      };
    });

    renderWithQueryClient(<WorkflowProbe fetchGraphQL={fetcher} />);

    await waitFor(() => {
      expect(screen.getByTestId("selected-id")).toHaveTextContent("evt_1");
    });

    act(() => {
      screen.getByRole("button", { name: "Next page" }).click();
    });

    await waitFor(() => {
      expect(screen.getByTestId("selected-id")).toHaveTextContent("evt_2");
    });
    expect(fetcher).toHaveBeenCalledWith(
      expect.objectContaining({
        variables: { limit: 50, afterCursor: "cursor_1" }
      })
    );
  });

  it("returns to the prior inbox cursor when loading the previous page", async () => {
    const fetcher = vi.fn(async ({ query, variables }: GraphQLRequest) => {
      if (query.includes("operatorInbox")) {
        return {
          data: {
            operatorInbox:
              variables.afterCursor === "cursor_1"
                ? { ...graphQLInbox, hasMore: false, nextCursor: null, afterCursor: "cursor_1" }
                : { ...graphQLInbox, hasMore: true, nextCursor: "cursor_1", afterCursor: null }
          }
        };
      }

      return {
        data: {
          operatorPacketReadiness: {
            type: "packet_readiness",
            ready: true,
            status: "packet_ready",
            allowedNextActions: [],
            blockerReasons: [],
            sourceLinks: [],
            requiredChecks: [],
            sourceWatermark: null
          }
        }
      };
    });

    renderWithQueryClient(<WorkflowProbe fetchGraphQL={fetcher} />);

    await waitFor(() => {
      expect(screen.getByTestId("selected-id")).toHaveTextContent("evt_1");
    });

    act(() => {
      screen.getByRole("button", { name: "Next page" }).click();
    });

    await waitFor(() => {
      expect(fetcher).toHaveBeenCalledWith(
        expect.objectContaining({ variables: { limit: 50, afterCursor: "cursor_1" } })
      );
    });

    act(() => {
      screen.getByRole("button", { name: "Previous page" }).click();
    });

    await waitFor(() => {
      expect(fetcher).toHaveBeenCalledWith(
        expect.objectContaining({ variables: { limit: 50, afterCursor: null } })
      );
    });
  });
});

function WorkflowProbe({
  fetchGraphQL,
  initialInboxSelectedId,
  initialSelectedId
}: {
  fetchGraphQL: Parameters<typeof useOperatorWorkflow>[0];
  initialInboxSelectedId?: string;
  initialSelectedId?: string;
}) {
  const workflow = useOperatorWorkflow(fetchGraphQL);

  useEffect(() => {
    if (initialSelectedId) {
      workflow.selectItem(initialSelectedId);
    }
  }, [initialSelectedId, workflow.selectItem]);

  useEffect(() => {
    if (initialInboxSelectedId) {
      workflow.selectInboxItem(initialInboxSelectedId);
    }
  }, [initialInboxSelectedId, workflow.selectInboxItem]);

  return (
    <div>
      <button type="button" onClick={() => workflow.selectItem("evt_external")}>
        Select external
      </button>
      <button type="button" onClick={workflow.loadNextInboxPage}>
        Next page
      </button>
      <button type="button" onClick={workflow.loadPreviousInboxPage}>
        Previous page
      </button>
      <p data-testid="selected-id">{workflow.selectedId ?? "none"}</p>
      <p>{workflow.selectedItem?.normalizedEventId ?? "none"}</p>
    </div>
  );
}

function renderWithQueryClient(ui: ReactElement) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });

  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>);
}
