import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen, waitFor } from "@testing-library/react";
import { useEffect } from "react";
import type { ReactElement } from "react";
import { describe, expect, it } from "vitest";
import { createGraphQLTestFetcher, graphQLInbox } from "./testSupport";
import { useOperatorWorkflow } from "./useOperatorWorkflow";

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
});

function WorkflowProbe({
  fetchGraphQL,
  initialSelectedId
}: {
  fetchGraphQL: Parameters<typeof useOperatorWorkflow>[0];
  initialSelectedId?: string;
}) {
  const workflow = useOperatorWorkflow(fetchGraphQL);

  useEffect(() => {
    if (initialSelectedId) {
      workflow.selectItem(initialSelectedId);
    }
  }, [initialSelectedId, workflow.selectItem]);

  return (
    <div>
      <button type="button" onClick={() => workflow.selectItem("evt_external")}>
        Select external
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
