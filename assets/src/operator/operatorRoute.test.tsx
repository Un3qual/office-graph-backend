import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import type { ReactElement } from "react";
import { describe, expect, it, vi } from "vitest";
import { OperatorRoute } from "./OperatorRoute";
import { createGraphQLTestFetcher, graphQLInbox, graphQLRunState } from "./testSupport";

describe("OperatorRoute", () => {
  it("renders the operator workbench from GraphQL projection data", async () => {
    const fetcher = createGraphQLTestFetcher({
      operatorInbox: {
        ...graphQLInbox,
        rows: [
          {
            ...graphQLInbox.rows[0],
            normalizedEventId: "evt_1",
            status: "ready_for_packet",
            allowedNextActions: ["prepare_packet"]
          }
        ]
      },
      operatorRunState: graphQLRunState
    });

    renderWithQueryClient(<OperatorRoute fetchGraphQL={fetcher} />);

    expect(screen.getByRole("heading", { name: "Operator Console" })).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: /evt_1/i })).toHaveAttribute(
      "aria-current",
      "true"
    );
    expect(screen.getByRole("region", { name: "Inbox" })).toHaveTextContent("Ready for packet");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1"
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "Prepare packet context"
    );
    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance"
      );
      expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
        "Owner acceptance"
      );
    });
  });

  it("shows the empty state without enabling workflow commands", async () => {
    const emptyFetcher = createGraphQLTestFetcher({
      operatorInbox: { ...graphQLInbox, empty: true, rows: [] }
    });

    renderWithQueryClient(<OperatorRoute fetchGraphQL={emptyFetcher} />);

    expect(await screen.findByText("No operator workflow items.")).toBeInTheDocument();
    expect(screen.getAllByText("No item selected").length).toBeGreaterThan(0);
    expect(screen.getByText("No packet readiness selected.")).toBeInTheDocument();
    expect(screen.queryByText("Loading item detail...")).not.toBeInTheDocument();
    expect(screen.queryByText("Loading readiness...")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /apply/i })).not.toBeInTheDocument();
  });

  it("shows GraphQL loading errors", async () => {
    const failingFetcher = vi.fn(async () => {
      throw new Error("GraphQL unavailable");
    });

    renderWithQueryClient(<OperatorRoute fetchGraphQL={failingFetcher} />);

    await waitFor(() => {
      expect(screen.getByText("GraphQL unavailable")).toBeInTheDocument();
    });
  });
});

function renderWithQueryClient(ui: ReactElement) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });

  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>);
}
