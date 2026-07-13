import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import { GraphQLResponseError } from "../../relay/fetchGraphQL";

import * as support from "./routeTestSupport";

describe("packet workspace route reads", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("renders an explicit loading state", () => {
    const request = support.deferredGraphQLResponse();

    support.renderWithRelay(vi.fn(() => request.promise));

    expect(screen.getByRole("status")).toHaveTextContent("Loading packets...");
  });

  it("renders a packet-specific empty state without stale detail", async () => {
    support.renderWithRelay(support.packetNetwork([]));

    expect(await screen.findByText("No packets are available.")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "No packet selected.",
    );
    expect(screen.queryByText("First packet")).not.toBeInTheDocument();
  });

  it("hides packet creation without an enabled backend affordance", async () => {
    support.renderWithRelay(
      support.packetNetwork(
        [],
        support.createPacketAffordance({
          state: "hidden",
          reasonCodes: ["policy_restricted"],
          blockerReasons: ["policy_restricted"],
        }),
      ),
    );

    await screen.findByText("No packets are available.");
    expect(screen.queryByRole("button", { name: "Create packet" })).not.toBeInTheDocument();
  });

  it("maps every server field error to packet controls and focuses the first invalid field", async () => {
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return support.packetConnectionResponse([], {}, support.createPacketAffordance());
      }

      expect(request.name).toBe("PacketsCreateWorkPacketMutation");
      throw new GraphQLResponseError(
        "Packet validation failed.",
        {
          errors: [
            {
              message: "Choose an allowed autonomy posture.",
              extensions: { code: "validation_failed", field: "autonomy_posture" },
            },
            {
              message: "Add current product context.",
              extensions: { code: "validation_failed", field: "context_summary" },
            },
            {
              message: "Describe how completion will be proven.",
              extensions: { code: "validation_failed", field: "success_criteria" },
            },
          ],
        } as unknown as GraphQLResponse,
        200,
        request.name,
      );
    });

    support.renderWithRelay(network);
    const createPacket = within(await screen.findByRole("region", { name: "Create packet" }));
    const submitButton = createPacket.getByRole("button", { name: "Create packet" });
    const form = submitButton.closest("form");
    expect(form).not.toBeNull();
    if (!form) throw new Error("Create packet form was not rendered.");

    fireEvent.submit(form);

    const context = createPacket.getByLabelText("Context summary");
    const criteria = createPacket.getByLabelText("Success criteria");
    await waitFor(() => expect(context).toHaveFocus());

    expect(createPacket.getByRole("alert")).toHaveTextContent("Add current product context.");
    expect(createPacket.getByRole("alert")).toHaveTextContent(
      "Describe how completion will be proven.",
    );
    expect(context).toHaveAttribute("aria-invalid", "true");
    expect(criteria).toHaveAttribute("aria-invalid", "true");
    const contextDescription = context.getAttribute("aria-describedby");
    const criteriaDescription = criteria.getAttribute("aria-describedby");
    expect(contextDescription).not.toBeNull();
    expect(criteriaDescription).not.toBeNull();
    expect(document.getElementById(contextDescription ?? "")).toHaveTextContent(
      "Add current product context.",
    );
    expect(document.getElementById(criteriaDescription ?? "")).toHaveTextContent(
      "Describe how completion will be proven.",
    );
  });

  it("renders a safe error without exposing Relay details", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    support.renderWithRelay(
      vi.fn(async () => {
        throw new Error("authorization policy secret_alpha denied packet_9");
      }),
    );

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load packets.");
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(document.body).not.toHaveTextContent("packet_9");
  });

  it("retries a failed packet list without requiring navigation", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let routeReads = 0;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        routeReads += 1;
        if (routeReads === 1) throw new Error("temporary packet list failure");
        return support.packetConnectionResponse([support.packet()]);
      }
      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(support.workspace());
      }
      throw new Error(`Unexpected Relay request in packet route test: ${request.name}`);
    });

    support.renderWithRelay(network);

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load packets");
    fireEvent.click(screen.getByRole("button", { name: "Retry packets" }));

    expect(await screen.findByRole("button", { name: /First packet/i })).toBeInTheDocument();
    expect(routeReads).toBe(2);
  });

  it("retries failed packet details without changing the selection", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let detailReads = 0;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return support.packetConnectionResponse([support.packet()]);
      }
      if (request.name === "PacketsWorkspaceDetailQuery") {
        detailReads += 1;
        if (detailReads === 1) throw new Error("temporary detail failure");
        return support.packetWorkspaceResponse(support.workspace());
      }
      throw new Error(`Unexpected Relay request in packet route test: ${request.name}`);
    });

    support.renderWithRelay(network);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Unable to load packet contract details",
    );
    fireEvent.click(screen.getByRole("button", { name: "Retry packet details" }));

    expect(await screen.findByRole("region", { name: "Version history" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /First packet/i })).toHaveAttribute(
      "aria-current",
      "true",
    );
    expect(detailReads).toBe(2);
  });

  it("refreshes authoritative packet data after a stale version conflict", async () => {
    const detail = support.workspace();
    let conflicted = false;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return support.packetConnectionResponse([support.packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        if (conflicted) {
          const versionTwo = support.packetVersion({ id: "version_2", versionNumber: 2 });
          return support.packetWorkspaceResponse(
            support.workspace({
              packet: support.packetWorkspacePacket({ currentVersionId: "version_2" }),
              currentVersion: versionTwo,
              versions: [support.packetVersion(), versionTwo],
            }),
          );
        }

        return support.packetWorkspaceResponse(detail);
      }

      expect(request.name).toBe("PacketsCreateWorkPacketVersionMutation");
      conflicted = true;
      throw new GraphQLResponseError(
        "The work packet version is stale.",
        {
          errors: [
            {
              message: "The work packet version is stale.",
              extensions: {
                code: "stale_packet_version",
                packet_id: "packet_1",
                current_version_id: "version_2",
              },
            },
          ],
        } as unknown as GraphQLResponse,
        200,
        request.name,
      );
    });

    support.renderWithRelay(network);
    await screen.findByText("Current version 1");
    fireEvent.click(screen.getByRole("button", { name: "Save new version" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("The work packet version is stale.");
    expect(await screen.findByText("Current version 2")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Version history" })).toHaveTextContent("Version 1");
  });

  it("keeps run start unavailable when the current affordance is disabled", async () => {
    support.renderWithRelay(
      support.packetWorkspaceNetwork(
        support.workspace({
          ready: false,
          status: "blocked",
          blockerReasons: ["missing_success_criteria"],
          allowedNextActions: [],
          commandAffordances: [
            support.startAffordance({
              state: "disabled",
              blockerReasons: ["missing_success_criteria"],
              reasonCodes: ["missing_success_criteria"],
              safeExplanation: "Resolve packet readiness blockers before starting a work run.",
            }),
          ],
        }),
      ),
    );

    await screen.findByText("Current version 1");
    expect(screen.queryByRole("button", { name: "Start work run" })).not.toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Packet version editor" })).not.toBeInTheDocument();
    expect(
      screen.getByText("Resolve packet readiness blockers before starting a work run."),
    ).toBeInTheDocument();
    expect(document.body).toHaveTextContent("missing_success_criteria");
  });

  it("loads the next Relay cursor page with an explicit loading state", async () => {
    const nextPage = support.deferredGraphQLResponse();
    const network = vi.fn(
      async (request, variables): Promise<GraphQLResponse> =>
        request.name === "PacketsWorkspaceDetailQuery"
          ? support.packetWorkspaceResponse(support.workspace())
          : variables.after === "cursor_1"
            ? nextPage.promise
            : support.packetConnectionResponse([support.packet()], {
                hasNextPage: true,
                endCursor: "cursor_1",
              }),
    );

    support.renderWithRelay(network);
    await screen.findByRole("button", { name: "Next" });
    await waitFor(() => expect(screen.getByRole("button", { name: "Next" })).toBeEnabled());

    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(screen.getByRole("status")).toHaveTextContent("Loading packet page...");
    expect(screen.queryByRole("button", { name: /First packet/i })).not.toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "No packet selected.",
    );
    nextPage.resolve(
      support.packetConnectionResponse(
        [support.packet({ id: "packet_2", title: "Second packet" })],
        {
          hasPreviousPage: true,
          startCursor: "cursor_2",
          endCursor: "cursor_2",
        },
      ),
    );

    await waitFor(() => {
      expect(support.lastVariablesFor(network, "PacketsRouteQuery")).toEqual({
        first: 50,
        after: "cursor_1",
        createdOperationId: null,
        loadCreatedPacket: false,
      });
      expect(screen.queryByRole("button", { name: /First packet/i })).not.toBeInTheDocument();
      expect(screen.getByRole("button", { name: /Second packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
    });
  });

  it("returns to the previous packet page when the next page fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(support.workspace());
      }

      if (variables.after === "cursor_1") {
        throw new Error("authorization policy secret_alpha denied packet_9");
      }

      return support.packetConnectionResponse([support.packet()], {
        hasNextPage: true,
        endCursor: "cursor_1",
      });
    });

    support.renderWithRelay(network);
    await screen.findByRole("button", { name: "Next" });
    await waitFor(() => expect(screen.getByRole("button", { name: "Next" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load packets.");
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(document.body).not.toHaveTextContent("packet_9");
    expect(screen.queryByRole("button", { name: /First packet/i })).not.toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "No packet selected.",
    );
    expect(screen.getByRole("button", { name: "Previous" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Next" })).toBeDisabled();

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
