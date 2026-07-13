import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fireEvent, screen, waitFor } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";

import * as support from "./routeTestSupport";

describe("packet workspace route reads", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("selects the first packet by default", async () => {
    support.renderWithRelay(
      support.packetNetwork([
        support.packet(),
        support.packet({ id: "packet_2", title: "Second packet" }),
      ]),
    );

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /First packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
    });
    expect(screen.getByRole("button", { name: /Second packet/i })).not.toHaveAttribute(
      "aria-current",
    );
  });

  it("updates route-local selection when a packet row is selected", async () => {
    support.renderWithRelay(
      support.packetNetwork([
        support.packet(),
        support.packet({ id: "packet_2", title: "Second packet" }),
      ]),
    );
    const secondRow = await screen.findByRole("button", { name: /Second packet/i });

    fireEvent.click(secondRow);

    await waitFor(() => {
      expect(secondRow).toHaveAttribute("aria-current", "true");
      expect(screen.getByRole("button", { name: /First packet/i })).not.toHaveAttribute(
        "aria-current",
      );
    });
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "Second packet",
    );
  });

  it("renders the selected packet summary and product navigation", async () => {
    support.renderWithRelay(
      support.packetNetwork([
        support.packet({
          currentVersionId: "version_current_7",
          operationId: "operation_sync_3",
          state: "ready_for_run",
          updatedAt: "2026-07-09T19:45:00Z",
        }),
      ]),
    );

    const selectedRow = await screen.findByRole("button", { name: /First packet/i });
    const detail = screen.getByRole("region", { name: "Packet detail" });

    expect(detail).toHaveTextContent("First packet");
    expect(detail).toHaveTextContent("Ready for run");
    expect(detail).toHaveTextContent("Jul 9, 2026, 7:45 PM UTC");
    expect(selectedRow).toHaveTextContent("Updated Jul 9, 2026, 7:45 PM UTC");
    expect(detail).toHaveTextContent("version_current_7");
    expect(detail).toHaveTextContent("operation_sync_3");
    expect(screen.getByText("Work packet workspace")).toBeInTheDocument();
    expect(screen.queryByText("Read-only queue")).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Operator" })).toHaveAttribute("href", "/operator");
    expect(screen.getByRole("link", { name: "Packets" })).toHaveAttribute("href", "/packets");
    expect(screen.getByRole("link", { name: "Packets" })).toHaveAttribute("aria-current", "page");
    await screen.findByText("Current version 1");
    expect(screen.queryByRole("combobox", { name: "Autonomy posture" })).not.toBeInTheDocument();
    expect(screen.getAllByText("Human supervised")).toHaveLength(2);
  });

  it("loads packet version history incrementally", async () => {
    const versionTwo = support.packetVersion({
      id: "version_2",
      versionNumber: 2,
      title: "Second",
    });
    const versionThree = support.packetVersion({
      id: "version_3",
      versionNumber: 3,
      title: "Third",
    });
    let detailPage = 1;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return support.packetConnectionResponse([support.packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        if (variables.versionAfter === "version_cursor_2") {
          detailPage = 2;
          return support.packetWorkspaceResponse(support.workspace({ versions: [versionThree] }), {
            hasNextPage: false,
            hasPreviousPage: true,
            startCursor: "version_cursor_3",
            endCursor: "version_cursor_3",
          });
        }

        return support.packetWorkspaceResponse(
          support.workspace({ versions: [support.packetVersion(), versionTwo] }),
          {
            hasNextPage: true,
            hasPreviousPage: false,
            startCursor: "version_cursor_1",
            endCursor: "version_cursor_2",
          },
        );
      }

      throw new Error(`Unexpected request ${request.name}`);
    });

    support.renderWithRelay(network);

    expect(await screen.findByText("Version 2")).toBeInTheDocument();
    expect(screen.queryByText("Version 3")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Next versions" }));

    expect(await screen.findByText("Version 3")).toBeInTheDocument();
    expect(detailPage).toBe(2);
    expect(support.lastVariablesFor(network, "PacketsWorkspaceDetailQuery")).toMatchObject({
      versionFirst: 2,
      versionAfter: "version_cursor_2",
    });
  });

  it("bounds the compact packet list while preserving list scrolling", () => {
    const styles = readFileSync(join(process.cwd(), "src/styles/packets.css"), "utf8");
    const compactBreakpoint = styles.indexOf("@media (max-width: 980px)");

    expect(compactBreakpoint).toBeGreaterThan(-1);

    const compactStyles = styles.slice(compactBreakpoint);
    const compactListPane = Array.from(
      compactStyles.matchAll(/\.packet-list-pane\s*\{([^}]*)\}/g),
      (match) => match[1],
    ).join("\n");

    expect(compactListPane).toMatch(/max-height:\s*\d+(?:\.\d+)?vh\s*;/);
    expect(compactListPane).not.toMatch(/min-height:/);
    expect(styles).toMatch(/\.packet-list-content\s*\{[^}]*overflow:\s*auto\s*;/);
  });

  it("uses the border design token for packet detail rows", () => {
    const styles = readFileSync(join(process.cwd(), "src/styles/packets.css"), "utf8");
    const detailRows = styles.match(/\.packet-detail-list div\s*\{([^}]*)\}/)?.[1] ?? "";

    expect(detailRows).toContain("border-bottom: 1px solid var(--og-color-border);");
    expect(detailRows).not.toContain("#edf1f3");
  });

  it("returns to the previous cursor page", async () => {
    const network = vi.fn(
      async (request, variables): Promise<GraphQLResponse> =>
        request.name === "PacketsWorkspaceDetailQuery"
          ? support.packetWorkspaceResponse(support.workspace())
          : variables.after === "cursor_1"
            ? support.packetConnectionResponse(
                [support.packet({ id: "packet_2", title: "Second packet" })],
                {
                  hasPreviousPage: true,
                  startCursor: "cursor_2",
                  endCursor: "cursor_2",
                },
              )
            : support.packetConnectionResponse([support.packet()], {
                hasNextPage: true,
                startCursor: "cursor_1",
                endCursor: "cursor_1",
              }),
    );

    support.renderWithRelay(network);
    await screen.findByRole("button", { name: "Next" });
    await waitFor(() => expect(screen.getByRole("button", { name: "Next" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    await waitFor(() => expect(screen.getByRole("button", { name: "Previous" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Previous" }));

    await waitFor(() => {
      expect(support.lastVariablesFor(network, "PacketsRouteQuery")).toEqual({
        first: 50,
        after: null,
        createdOperationId: null,
        loadCreatedPacket: false,
      });
      expect(screen.getByRole("button", { name: /First packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    });
  });
});
