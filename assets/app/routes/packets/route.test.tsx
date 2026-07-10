import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { RelayEnvironmentProvider } from "react-relay";
import { MemoryRouter } from "react-router";
import {
  Environment,
  Network,
  RecordSource,
  Store,
  type FetchFunction,
  type GraphQLResponse
} from "relay-runtime";
import { describe, expect, it, vi } from "vitest";
import { getOfficeGraphDataID } from "../../relay/environment";
import PacketsRoute from "./route";

describe("packet workspace route", () => {
  it("renders an explicit loading state", () => {
    const request = deferredGraphQLResponse();

    renderWithRelay(vi.fn(() => request.promise));

    expect(screen.getByRole("status")).toHaveTextContent("Loading packets...");
  });

  it("renders a packet-specific empty state without stale detail", async () => {
    renderWithRelay(packetNetwork([]));

    expect(await screen.findByText("No packets are available.")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "No packet selected."
    );
    expect(screen.queryByText("First packet")).not.toBeInTheDocument();
  });

  it("renders a safe error without exposing Relay details", async () => {
    renderWithRelay(
      vi.fn(async () => {
        throw new Error("authorization policy secret_alpha denied packet_9");
      })
    );

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load packets.");
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(document.body).not.toHaveTextContent("packet_9");
  });

  it("selects the first packet by default", async () => {
    renderWithRelay(
      packetNetwork([packet(), packet({ id: "packet_2", title: "Second packet" })])
    );

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /First packet/i })).toHaveAttribute(
        "aria-current",
        "true"
      );
    });
    expect(screen.getByRole("button", { name: /Second packet/i })).not.toHaveAttribute(
      "aria-current"
    );
  });

  it("updates route-local selection when a packet row is selected", async () => {
    renderWithRelay(
      packetNetwork([packet(), packet({ id: "packet_2", title: "Second packet" })])
    );
    const secondRow = await screen.findByRole("button", { name: /Second packet/i });

    fireEvent.click(secondRow);

    await waitFor(() => {
      expect(secondRow).toHaveAttribute("aria-current", "true");
      expect(screen.getByRole("button", { name: /First packet/i })).not.toHaveAttribute(
        "aria-current"
      );
    });
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "Second packet"
    );
  });

  it("renders the selected packet summary and product navigation", async () => {
    renderWithRelay(
      packetNetwork([
        packet({
          currentVersionId: "version_current_7",
          operationId: "operation_sync_3",
          state: "ready_for_run",
          updatedAt: "2026-07-09T19:45:00Z"
        })
      ])
    );

    const detail = await screen.findByRole("region", { name: "Packet detail" });
    const selectedRow = screen.getByRole("button", { name: /First packet/i });

    expect(detail).toHaveTextContent("First packet");
    expect(detail).toHaveTextContent("Ready for run");
    expect(detail).toHaveTextContent("Jul 9, 2026, 7:45 PM UTC");
    expect(selectedRow).toHaveTextContent("Updated Jul 9, 2026, 7:45 PM UTC");
    expect(detail).toHaveTextContent("version_current_7");
    expect(detail).toHaveTextContent("operation_sync_3");
    expect(screen.getByRole("link", { name: "Operator" })).toHaveAttribute("href", "/operator");
    expect(screen.getByRole("link", { name: "Packets" })).toHaveAttribute("href", "/packets");
    expect(screen.getByRole("link", { name: "Packets" })).toHaveAttribute(
      "aria-current",
      "page"
    );
  });

  it("loads the next Relay cursor page with an explicit loading state", async () => {
    const nextPage = deferredGraphQLResponse();
    const network = vi.fn(
      async (_request, variables): Promise<GraphQLResponse> =>
        variables.after === "cursor_1"
          ? nextPage.promise
          : packetConnectionResponse([packet()], {
              hasNextPage: true,
              endCursor: "cursor_1"
            })
    );

    renderWithRelay(network);
    expect(await screen.findByRole("button", { name: "Next" })).toBeEnabled();

    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(screen.getByRole("status")).toHaveTextContent("Loading packet page...");
    nextPage.resolve(
      packetConnectionResponse([packet({ id: "packet_2", title: "Second packet" })], {
        hasPreviousPage: true,
        startCursor: "cursor_2",
        endCursor: "cursor_2"
      })
    );

    await waitFor(() => {
      expect(network.mock.lastCall?.[1]).toEqual({ first: 50, after: "cursor_1" });
      expect(screen.queryByRole("button", { name: /First packet/i })).not.toBeInTheDocument();
      expect(screen.getByRole("button", { name: /Second packet/i })).toHaveAttribute(
        "aria-current",
        "true"
      );
    });
  });

  it("clears packet content and disables pagination when the next page fails", async () => {
    const network = vi.fn(async (_request, variables): Promise<GraphQLResponse> => {
      if (variables.after === "cursor_1") {
        throw new Error("authorization policy secret_alpha denied packet_9");
      }

      return packetConnectionResponse([packet()], {
        hasNextPage: true,
        endCursor: "cursor_1"
      });
    });

    renderWithRelay(network);
    fireEvent.click(await screen.findByRole("button", { name: "Next" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load packets.");
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(document.body).not.toHaveTextContent("packet_9");
    expect(screen.queryByRole("button", { name: /First packet/i })).not.toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "No packet selected."
    );
    expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Next" })).toBeDisabled();
  });

  it("bounds the compact packet list while preserving list scrolling", () => {
    const styles = readFileSync(join(process.cwd(), "src/styles/global.css"), "utf8");
    const compactBreakpoint = styles.indexOf("@media (max-width: 980px)");

    expect(compactBreakpoint).toBeGreaterThan(-1);

    const compactStyles = styles.slice(compactBreakpoint);
    const compactListPane = Array.from(
      compactStyles.matchAll(/\.packet-list-pane\s*\{([^}]*)\}/g),
      (match) => match[1]
    ).join("\n");

    expect(compactListPane).toMatch(/max-height:\s*\d+(?:\.\d+)?vh\s*;/);
    expect(compactListPane).not.toMatch(/min-height:/);
    expect(styles).toMatch(/\.packet-list-content\s*\{[^}]*overflow:\s*auto\s*;/);
  });

  it("uses the border design token for packet detail rows", () => {
    const styles = readFileSync(join(process.cwd(), "src/styles/global.css"), "utf8");
    const detailRows = styles.match(/\.packet-detail-list div\s*\{([^}]*)\}/)?.[1] ?? "";

    expect(detailRows).toContain(
      "border-bottom: 1px solid var(--og-color-border);"
    );
    expect(detailRows).not.toContain("#edf1f3");
  });

  it("returns to the previous cursor page", async () => {
    const network = vi.fn(async (_request, variables): Promise<GraphQLResponse> =>
      variables.after === "cursor_1"
        ? packetConnectionResponse([packet({ id: "packet_2", title: "Second packet" })], {
            hasPreviousPage: true,
            startCursor: "cursor_2",
            endCursor: "cursor_2"
          })
        : packetConnectionResponse([packet()], {
            hasNextPage: true,
            startCursor: "cursor_1",
            endCursor: "cursor_1"
          })
    );

    renderWithRelay(network);
    fireEvent.click(await screen.findByRole("button", { name: "Next" }));
    const previousButton = await screen.findByRole("button", { name: "Previous" });

    await waitFor(() => expect(previousButton).toBeEnabled());
    fireEvent.click(previousButton);

    await waitFor(() => {
      expect(network.mock.lastCall?.[1]).toEqual({ first: 50, after: null });
      expect(screen.getByRole("button", { name: /First packet/i })).toHaveAttribute(
        "aria-current",
        "true"
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    });
  });
});

function renderWithRelay(network: FetchFunction) {
  const environment = new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(network),
    store: new Store(new RecordSource())
  });

  return render(
    <MemoryRouter initialEntries={["/packets"]}>
      <RelayEnvironmentProvider environment={environment}>
        <PacketsRoute />
      </RelayEnvironmentProvider>
    </MemoryRouter>
  );
}

function packetNetwork(packets: ReturnType<typeof packet>[]) {
  return vi.fn(async (): Promise<GraphQLResponse> => packetConnectionResponse(packets));
}

function packetConnectionResponse(
  packets: ReturnType<typeof packet>[],
  pageInfoOverrides: Partial<PageInfoPayload> = {}
): GraphQLResponse {
  return {
    data: {
      listWorkPackets: {
        edges: packets.map((node, index) => ({
          cursor: `cursor_${index + 1}`,
          node
        })),
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: packets.length > 0 ? "cursor_1" : null,
          endCursor: packets.length > 0 ? `cursor_${packets.length}` : null,
          ...pageInfoOverrides
        }
      }
    }
  };
}

function packet(overrides: Partial<PacketPayload> = {}) {
  return {
    __typename: "WorkPacket",
    id: "packet_1",
    title: "First packet",
    state: "active",
    currentVersionId: "version_1",
    operationId: "operation_1",
    updatedAt: "2026-07-09T12:00:00Z",
    ...overrides
  };
}

function deferredGraphQLResponse() {
  let resolve!: (value: GraphQLResponse) => void;
  const promise = new Promise<GraphQLResponse>((resolvePromise) => {
    resolve = resolvePromise;
  });

  return { promise, resolve };
}

type PacketPayload = {
  id: string;
  title: string;
  state: string;
  currentVersionId: string | null;
  operationId: string | null;
  updatedAt: string;
};

type PageInfoPayload = {
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  startCursor: string | null;
  endCursor: string | null;
};
