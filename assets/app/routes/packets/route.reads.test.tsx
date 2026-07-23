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
        support.packet({ id: support.packetIdentity.relayId }),
        support.packet({ id: support.secondPacketIdentity.relayId, title: "Second packet" }),
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
    await waitFor(() => {
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${support.packetIdentity.relayId}`,
      );
    });
    expect(screen.getByTestId("route-location")).not.toHaveTextContent(
      support.packetIdentity.rawId,
    );
  });

  it("selects a packetId already present on the first page without duplicating it", async () => {
    const selectedPacket = support.packet({
      id: support.secondPacketIdentity.relayId,
      title: "Linked packet",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        expect(variables).toEqual({
          first: 50,
          after: null,
          createdOperationId: null,
          loadCreatedPacket: false,
          packetId: support.secondPacketIdentity.relayId,
          loadLinkedPacket: true,
        });
        return support.packetConnectionResponse(
          [support.packet(), selectedPacket],
          {},
          support.createPacketAffordance(),
          [],
          [selectedPacket],
        );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(
          support.workspace({
            packet: support.packetWorkspacePacket({
              id: support.secondPacketIdentity.rawId,
              title: "Linked packet",
            }),
          }),
        );
      }

      throw new Error(`Unexpected request ${request.name}`);
    });

    support.renderWithRelay(network, `/packets?packetId=${support.secondPacketIdentity.relayId}`);

    const selectedRows = await screen.findAllByRole("button", { name: /Linked packet/i });
    expect(selectedRows).toHaveLength(1);
    expect(selectedRows[0]).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "Linked packet",
    );
    expect(screen.getByTestId("route-location")).toHaveTextContent(
      `/packets?packetId=${support.secondPacketIdentity.relayId}`,
    );
  });

  it("loads an authorized packetId outside the first page and preserves normal row selection", async () => {
    const linkedPacket = support.packet({
      id: support.secondPacketIdentity.relayId,
      title: "Linked packet",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        const selectedPacket =
          variables.packetId === support.secondPacketIdentity.relayId
            ? linkedPacket
            : support.packet({ id: support.packetIdentity.relayId });

        return support.packetConnectionResponse(
          [support.packet({ id: support.packetIdentity.relayId })],
          {},
          support.createPacketAffordance(),
          [],
          [selectedPacket],
        );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        const packet =
          variables.id === support.secondPacketIdentity.relayId
            ? support.packetWorkspacePacket({
                id: support.secondPacketIdentity.rawId,
                title: "Linked packet",
              })
            : support.packetWorkspacePacket({ id: support.packetIdentity.rawId });
        return support.packetWorkspaceResponse(support.workspace({ packet }));
      }

      throw new Error(`Unexpected request ${request.name}`);
    });

    support.renderWithRelay(network, `/packets?packetId=${support.secondPacketIdentity.relayId}`);

    const linkedRow = await screen.findByRole("button", { name: /Linked packet/i });
    expect(linkedRow).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "Linked packet",
    );

    fireEvent.click(screen.getByRole("button", { name: /First packet/i }));

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /First packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${support.packetIdentity.relayId}`,
      );
    });
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent("First packet");
  });

  it.each([
    "d29ya19wYWNrZXQ6MzIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDAw",
    "d29ya19wYWNrZXQ6NDIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDAw",
    "not-a-relay-id",
  ])("retains unavailable packetId %s without falling back to the first row", async (packetId) => {
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        const response = support.packetConnectionResponse([
          support.packet({ id: support.packetIdentity.relayId }),
        ]);

        return packetId === "not-a-relay-id"
          ? ({
              ...response,
              errors: [
                {
                  message: "invalid primary key provided",
                  path: ["linkedPacket"],
                  locations: [{ line: 1, column: 1 }],
                },
              ],
            } as GraphQLResponse)
          : response;
      }

      throw new Error(`The unavailable selection must not load detail: ${request.name}`);
    });

    support.renderWithRelay(network, `/packets?packetId=${packetId}`);

    expect(await screen.findByRole("button", { name: /First packet/i })).not.toHaveAttribute(
      "aria-current",
    );
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "No packet selected.",
    );
    expect(screen.getByTestId("route-location")).toHaveTextContent(`/packets?packetId=${packetId}`);
  });

  it("clears stale detail when the URL changes to an unavailable packetId", async () => {
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return support.packetConnectionResponse(
          [support.packet({ id: support.packetIdentity.relayId })],
          {},
          support.createPacketAffordance(),
          [],
          variables.packetId === support.packetIdentity.relayId
            ? [support.packet({ id: support.packetIdentity.relayId })]
            : [],
        );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(support.workspace());
      }

      throw new Error(`Unexpected request ${request.name}`);
    });

    const view = support.renderWithRelay(
      network,
      `/packets?packetId=${support.packetIdentity.relayId}`,
    );

    expect(await screen.findByRole("heading", { name: "First packet" })).toBeInTheDocument();
    const unavailablePacketId = "d29ya19wYWNrZXQ6MzIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDAw";
    view.navigate(`/packets?packetId=${unavailablePacketId}`);

    await waitFor(() => {
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${unavailablePacketId}`,
      );
      expect(screen.queryByRole("heading", { name: "First packet" })).not.toBeInTheDocument();
      expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
        "No packet selected.",
      );
      expect(screen.getByRole("button", { name: /First packet/i })).not.toHaveAttribute(
        "aria-current",
      );
    });
  });

  it("preserves a row-selected packetId while paging forward and backward", async () => {
    const firstPacket = support.packet({ id: support.packetIdentity.relayId });
    const secondPacket = support.packet({
      id: support.secondPacketIdentity.relayId,
      title: "Second packet",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        const linkedPacket =
          variables.packetId === support.secondPacketIdentity.relayId ? [secondPacket] : [];

        return variables.after === "cursor_2"
          ? support.packetConnectionResponse(
              [
                support.packet({
                  id: "d29ya19wYWNrZXQ6MzIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDAw",
                  title: "Third packet",
                }),
              ],
              {
                hasPreviousPage: true,
                startCursor: "cursor_3",
                endCursor: "cursor_3",
              },
              support.createPacketAffordance(),
              [],
              linkedPacket,
            )
          : support.packetConnectionResponse(
              [firstPacket, secondPacket],
              {
                hasNextPage: true,
                startCursor: "cursor_1",
                endCursor: "cursor_2",
              },
              support.createPacketAffordance(),
              [],
              linkedPacket,
            );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(
          support.workspace({
            packet:
              variables.id === support.secondPacketIdentity.relayId
                ? support.packetWorkspacePacket({
                    id: support.secondPacketIdentity.rawId,
                    title: "Second packet",
                  })
                : support.packetWorkspacePacket({ id: support.packetIdentity.rawId }),
          }),
        );
      }

      throw new Error(`Unexpected request ${request.name}`);
    });

    support.renderWithRelay(network);
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

    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /Second packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${support.secondPacketIdentity.relayId}`,
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeEnabled();
    });

    fireEvent.click(screen.getByRole("button", { name: "Previous" }));

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /Second packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${support.secondPacketIdentity.relayId}`,
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    });
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

  it("moves only default-origin selection when paging forward and backward", async () => {
    const network = vi.fn(
      async (request, variables): Promise<GraphQLResponse> =>
        request.name === "PacketsWorkspaceDetailQuery"
          ? support.packetWorkspaceResponse(support.workspace())
          : variables.after === "cursor_1"
            ? support.packetConnectionResponse(
                [
                  support.packet({
                    id: support.secondPacketIdentity.relayId,
                    title: "Second packet",
                  }),
                ],
                {
                  hasPreviousPage: true,
                  startCursor: "cursor_2",
                  endCursor: "cursor_2",
                },
              )
            : support.packetConnectionResponse(
                [support.packet({ id: support.packetIdentity.relayId })],
                {
                  hasNextPage: true,
                  startCursor: "cursor_1",
                  endCursor: "cursor_1",
                },
              ),
    );

    support.renderWithRelay(network);
    await screen.findByRole("button", { name: "Next" });
    await waitFor(() => expect(screen.getByRole("button", { name: "Next" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Previous" })).toBeEnabled();
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${support.secondPacketIdentity.relayId}`,
      );
    });
    fireEvent.click(screen.getByRole("button", { name: "Previous" }));

    await waitFor(() => {
      expect(support.lastVariablesFor(network, "PacketsRouteQuery")).toMatchObject({
        first: 50,
        after: null,
        createdOperationId: null,
        loadCreatedPacket: false,
      });
      expect(screen.getByRole("button", { name: /First packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${support.packetIdentity.relayId}`,
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    });
  });

  it("preserves an explicit off-page packetId while paging forward and backward", async () => {
    const explicitPacket = support.packet({
      id: support.secondPacketIdentity.relayId,
      title: "Explicit packet",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        expect(variables.packetId).toBe(support.secondPacketIdentity.relayId);

        return variables.after === "cursor_1"
          ? support.packetConnectionResponse(
              [
                support.packet({
                  id: "d29ya19wYWNrZXQ6MzIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDAw",
                  title: "Second page packet",
                }),
              ],
              {
                hasPreviousPage: true,
                startCursor: "cursor_2",
                endCursor: "cursor_2",
              },
              support.createPacketAffordance(),
              [],
              [explicitPacket],
            )
          : support.packetConnectionResponse(
              [support.packet({ id: support.packetIdentity.relayId })],
              {
                hasNextPage: true,
                startCursor: "cursor_1",
                endCursor: "cursor_1",
              },
              support.createPacketAffordance(),
              [],
              [explicitPacket],
            );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        expect(variables.id).toBe(support.secondPacketIdentity.relayId);
        return support.packetWorkspaceResponse(
          support.workspace({
            packet: support.packetWorkspacePacket({
              id: support.secondPacketIdentity.rawId,
              title: "Explicit packet",
            }),
          }),
        );
      }

      throw new Error(`Unexpected request ${request.name}`);
    });

    support.renderWithRelay(network, `/packets?packetId=${support.secondPacketIdentity.relayId}`);

    expect(await screen.findByRole("button", { name: /Explicit packet/i })).toHaveAttribute(
      "aria-current",
      "true",
    );
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /Explicit packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${support.secondPacketIdentity.relayId}`,
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeEnabled();
    });

    fireEvent.click(screen.getByRole("button", { name: "Previous" }));

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /Explicit packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByTestId("route-location")).toHaveTextContent(
        `/packets?packetId=${support.secondPacketIdentity.relayId}`,
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    });
  });
});
