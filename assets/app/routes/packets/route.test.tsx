import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { RelayEnvironmentProvider } from "react-relay";
import { MemoryRouter } from "react-router";
import {
  Environment,
  Network,
  RecordSource,
  Store,
  type FetchFunction,
  type GraphQLResponse,
} from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import { getOfficeGraphDataID } from "../../relay/environment";
import { GraphQLResponseError } from "../../relay/fetchGraphQL";
import PacketsRoute from "./route";

describe("packet workspace route", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("renders an explicit loading state", () => {
    const request = deferredGraphQLResponse();

    renderWithRelay(vi.fn(() => request.promise));

    expect(screen.getByRole("status")).toHaveTextContent("Loading packets...");
  });

  it("renders a packet-specific empty state without stale detail", async () => {
    renderWithRelay(packetNetwork([]));

    expect(await screen.findByText("No packets are available.")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "No packet selected.",
    );
    expect(screen.queryByText("First packet")).not.toBeInTheDocument();
  });

  it("hides packet creation without an enabled backend affordance", async () => {
    renderWithRelay(
      packetNetwork(
        [],
        createPacketAffordance({
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
        return packetConnectionResponse([], {}, createPacketAffordance());
      }

      expect(request.name).toBe("PacketsCreateWorkPacketMutation");
      throw new GraphQLResponseError(
        "Packet validation failed.",
        {
          errors: [
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

    renderWithRelay(network);
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
    renderWithRelay(
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
        return packetConnectionResponse([packet()]);
      }
      if (request.name === "PacketsWorkspaceDetailQuery") {
        return packetWorkspaceResponse(workspace());
      }
      throw new Error(`Unexpected Relay request in packet route test: ${request.name}`);
    });

    renderWithRelay(network);

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load packets");
    fireEvent.click(screen.getByRole("button", { name: "Retry packets" }));

    expect(await screen.findByRole("button", { name: /First packet/i })).toBeInTheDocument();
    expect(routeReads).toBe(2);
  });

  it("selects the first packet by default", async () => {
    renderWithRelay(packetNetwork([packet(), packet({ id: "packet_2", title: "Second packet" })]));

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

  it("retries failed packet details without changing the selection", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let detailReads = 0;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return packetConnectionResponse([packet()]);
      }
      if (request.name === "PacketsWorkspaceDetailQuery") {
        detailReads += 1;
        if (detailReads === 1) throw new Error("temporary detail failure");
        return packetWorkspaceResponse(workspace());
      }
      throw new Error(`Unexpected Relay request in packet route test: ${request.name}`);
    });

    renderWithRelay(network);

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

  it("updates route-local selection when a packet row is selected", async () => {
    renderWithRelay(packetNetwork([packet(), packet({ id: "packet_2", title: "Second packet" })]));
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
    renderWithRelay(
      packetNetwork([
        packet({
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

  it("creates a packet, selects it, and starts a new attempt after success", async () => {
    let created = false;
    const idempotencyKeys: string[] = [];
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return packetConnectionResponse(
          created
            ? [
                packet(),
                packet({
                  id: "relay_packet_created",
                  operationId: "operation_created",
                  title: "Created packet",
                }),
              ]
            : [packet()],
        );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        if (variables.id !== "relay_packet_created") {
          return packetWorkspaceResponse(workspace());
        }

        return packetWorkspaceResponse(
          workspace({
            packet: packetWorkspacePacket({
              id: "raw_packet_created",
              title: "Created packet",
              currentVersionId: "version_created",
            }),
            currentVersion: packetVersion({
              id: "version_created",
              title: "Created packet",
            }),
            versions: [packetVersion({ id: "version_created", title: "Created packet" })],
          }),
        );
      }

      expect(request.name).toBe("PacketsCreateWorkPacketMutation");
      idempotencyKeys.push(variables.input.idempotencyKey);
      expect(variables.input).toMatchObject({
        title: "Created packet",
        objective: "Ship the packet workspace",
        contextSummary: "Current product context",
        requirements: "Preserve immutable history",
        successCriteria: "The required check passes",
        autonomyPosture: "human_supervised",
        sourceGraphItemIds: ["graph_1"],
        verificationCheckIds: ["check_1"],
      });
      created = true;

      return {
        data: {
          createWorkPacket: {
            command: "create_work_packet",
            operationId: "operation_created",
            affectedIds: [
              { type: "work_packet", id: "raw_packet_created" },
              { type: "work_packet_version", id: "version_created" },
            ],
            packet: {
              id: "raw_packet_created",
              currentVersionId: "version_created",
              title: "Created packet",
              state: "ready",
            },
            packetVersion: {
              id: "version_created",
              versionNumber: 1,
              lifecycleState: "ready",
            },
          },
        },
      };
    });

    renderWithRelay(network);
    await screen.findByRole("button", { name: /First packet/i });
    const createPacket = within(screen.getByRole("region", { name: "Create packet" }));

    fireEvent.change(createPacket.getByLabelText("Packet title"), {
      target: { value: "Created packet" },
    });
    fireEvent.change(createPacket.getByLabelText("Objective"), {
      target: { value: "Ship the packet workspace" },
    });
    fireEvent.change(createPacket.getByLabelText("Context summary"), {
      target: { value: "Current product context" },
    });
    fireEvent.change(createPacket.getByLabelText("Requirements"), {
      target: { value: "Preserve immutable history" },
    });
    fireEvent.change(createPacket.getByLabelText("Success criteria"), {
      target: { value: "The required check passes" },
    });
    fireEvent.change(createPacket.getByLabelText("Source graph item IDs"), {
      target: { value: "graph_1" },
    });
    fireEvent.change(createPacket.getByLabelText("Verification check IDs"), {
      target: { value: "check_1" },
    });
    fireEvent.click(createPacket.getByRole("button", { name: "Create packet" }));

    await waitFor(() => {
      expect(screen.getByRole("button", { name: /Created packet/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
    });
    expect(await screen.findByText("Current version 1")).toBeInTheDocument();

    fireEvent.click(createPacket.getByRole("button", { name: "Create packet" }));

    await waitFor(() => expect(idempotencyKeys).toHaveLength(2));
    expect(idempotencyKeys[1]).not.toBe(idempotencyKeys[0]);
  });

  it("loads and selects a newly created packet outside the first page", async () => {
    let created = false;
    const createdPacket = packet({
      id: "relay_packet_created",
      operationId: "operation_created",
      title: "Created packet",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        if (variables.after === "cursor_1") {
          return packetConnectionResponse([packet({ id: "packet_2", title: "Second packet" })]);
        }

        return packetConnectionResponse(
          [packet()],
          created ? {} : { hasNextPage: true, endCursor: "cursor_1" },
          createPacketAffordance(),
          created ? [createdPacket] : [],
        );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return packetWorkspaceResponse(workspace());
      }

      expect(request.name).toBe("PacketsCreateWorkPacketMutation");
      created = true;
      return {
        data: {
          createWorkPacket: {
            command: "create_work_packet",
            operationId: "operation_created",
            affectedIds: [
              { type: "work_packet", id: "raw_packet_created" },
              { type: "work_packet_version", id: "version_created" },
            ],
            packet: {
              id: "raw_packet_created",
              currentVersionId: "version_created",
              title: "Created packet",
              state: "ready",
            },
            packetVersion: {
              id: "version_created",
              versionNumber: 1,
              lifecycleState: "ready",
            },
          },
        },
      };
    });

    renderWithRelay(network);
    await screen.findByRole("button", { name: /First packet/i });
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    await screen.findByRole("button", { name: /Second packet/i });

    const createPacket = within(screen.getByRole("region", { name: "Create packet" }));
    fireEvent.change(createPacket.getByLabelText("Packet title"), {
      target: { value: "Created packet" },
    });
    fireEvent.change(createPacket.getByLabelText("Objective"), {
      target: { value: "Ship the packet workspace" },
    });
    fireEvent.change(createPacket.getByLabelText("Context summary"), {
      target: { value: "Current product context" },
    });
    fireEvent.change(createPacket.getByLabelText("Requirements"), {
      target: { value: "Preserve immutable history" },
    });
    fireEvent.change(createPacket.getByLabelText("Success criteria"), {
      target: { value: "The required check passes" },
    });
    fireEvent.change(createPacket.getByLabelText("Source graph item IDs"), {
      target: { value: "graph_1" },
    });
    fireEvent.change(createPacket.getByLabelText("Verification check IDs"), {
      target: { value: "check_1" },
    });
    fireEvent.click(createPacket.getByRole("button", { name: "Create packet" }));

    const createdRow = await screen.findByRole("button", { name: /Created packet/i });
    await waitFor(() => expect(createdRow).toHaveAttribute("aria-current", "true"));
    expect(lastVariablesFor(network, "PacketsRouteQuery")).toEqual({
      first: 50,
      after: null,
      createdOperationId: "operation_created",
      loadCreatedPacket: true,
    });
    expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
  });

  it("creates a new version with the exact current id and preserves immutable history", async () => {
    let detail = workspace();
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return packetConnectionResponse([packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return packetWorkspaceResponse(detail);
      }

      expect(request.name).toBe("PacketsCreateWorkPacketVersionMutation");
      expect(variables.input).toMatchObject({
        packetId: "packet_1",
        expectedCurrentVersionId: "version_1",
        title: "Revised packet",
        sourceGraphItemIds: ["graph_1"],
        verificationCheckIds: ["check_1"],
      });

      const versionTwo = packetVersion({
        id: "version_2",
        versionNumber: 2,
        title: "Revised packet",
      });
      detail = workspace({
        packet: packetWorkspacePacket({
          title: "Revised packet",
          currentVersionId: "version_2",
        }),
        currentVersion: versionTwo,
        versions: [packetVersion(), versionTwo],
      });

      return {
        data: {
          createWorkPacketVersion: {
            command: "create_work_packet_version",
            operationId: "operation_2",
            affectedIds: [
              { type: "work_packet", id: "packet_1" },
              { type: "work_packet_version", id: "version_2" },
            ],
            packet: {
              id: "packet_1",
              currentVersionId: "version_2",
              title: "Revised packet",
              state: "ready",
            },
            packetVersion: {
              id: "version_2",
              versionNumber: 2,
              lifecycleState: "ready",
            },
          },
        },
      };
    });

    renderWithRelay(network);
    await screen.findByText("Current version 1");
    fireEvent.change(screen.getByLabelText("Version title"), {
      target: { value: "Revised packet" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save new version" }));

    expect(await screen.findByText("Current version 2")).toBeInTheDocument();
    const history = screen.getByRole("region", { name: "Version history" });
    expect(history).toHaveTextContent("Version 1");
    expect(history).toHaveTextContent("Version 2");
  });

  it("loads packet version history incrementally", async () => {
    const versionTwo = packetVersion({ id: "version_2", versionNumber: 2, title: "Second" });
    const versionThree = packetVersion({ id: "version_3", versionNumber: 3, title: "Third" });
    let detailPage = 1;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return packetConnectionResponse([packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        if (variables.versionAfter === "version_cursor_2") {
          detailPage = 2;
          return packetWorkspaceResponse(workspace({ versions: [versionThree] }), {
            hasNextPage: false,
            hasPreviousPage: true,
            startCursor: "version_cursor_3",
            endCursor: "version_cursor_3",
          });
        }

        return packetWorkspaceResponse(workspace({ versions: [packetVersion(), versionTwo] }), {
          hasNextPage: true,
          hasPreviousPage: false,
          startCursor: "version_cursor_1",
          endCursor: "version_cursor_2",
        });
      }

      throw new Error(`Unexpected request ${request.name}`);
    });

    renderWithRelay(network);

    expect(await screen.findByText("Version 2")).toBeInTheDocument();
    expect(screen.queryByText("Version 3")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Next versions" }));

    expect(await screen.findByText("Version 3")).toBeInTheDocument();
    expect(detailPage).toBe(2);
    expect(lastVariablesFor(network, "PacketsWorkspaceDetailQuery")).toMatchObject({
      versionFirst: 2,
      versionAfter: "version_cursor_2",
    });
  });

  it("refreshes authoritative packet data after a stale version conflict", async () => {
    const detail = workspace();
    let conflicted = false;
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return packetConnectionResponse([packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        if (conflicted) {
          const versionTwo = packetVersion({ id: "version_2", versionNumber: 2 });
          return packetWorkspaceResponse(
            workspace({
              packet: packetWorkspacePacket({ currentVersionId: "version_2" }),
              currentVersion: versionTwo,
              versions: [packetVersion(), versionTwo],
            }),
          );
        }

        return packetWorkspaceResponse(detail);
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

    renderWithRelay(network);
    await screen.findByText("Current version 1");
    fireEvent.click(screen.getByRole("button", { name: "Save new version" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("The work packet version is stale.");
    expect(await screen.findByText("Current version 2")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Version history" })).toHaveTextContent("Version 1");
  });

  it("starts a run only from an enabled current affordance and links the returned state", async () => {
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return packetConnectionResponse([packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return packetWorkspaceResponse(workspace());
      }

      expect(request.name).toBe("PacketsStartWorkRunMutation");
      expect(variables.input).toMatchObject({
        packetVersionId: "version_1",
        sourceSurface: "packet_workspace",
        reason: "Start work from the packet workspace.",
        authorityPosture: "human_supervised",
      });

      return {
        data: {
          startWorkRun: {
            command: "start_work_run",
            operationId: "operation_run",
            affectedIds: [{ type: "work_run", id: "run_1" }],
            run: {
              id: "run_1",
              executionState: "pending",
              verificationState: "pending",
            },
            requiredChecks: [
              { id: "required_1", verificationCheckId: "check_1", state: "pending" },
            ],
          },
        },
      };
    });

    renderWithRelay(network);
    await screen.findByText("Current version 1");
    fireEvent.click(screen.getByRole("button", { name: "Start work run" }));

    const runLink = await screen.findByRole("link", { name: /Open run run_1/i });
    expect(runLink).toHaveAttribute("href", "/operator?runId=run_1");
    expect(runLink).toHaveAttribute("data-discover", "true");
    expect(screen.getByRole("region", { name: "Run result" })).toHaveTextContent(
      "Execution pending",
    );
  });

  it("clears packet-scoped command results when the selected packet changes", async () => {
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return packetConnectionResponse([
          packet(),
          packet({
            id: "packet_2",
            title: "Second packet",
            currentVersionId: "version_2",
          }),
        ]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return variables.id === "packet_2"
          ? packetWorkspaceResponse(
              workspace({
                packet: packetWorkspacePacket({
                  id: "packet_2",
                  title: "Second packet",
                  currentVersionId: "version_2",
                }),
                currentVersion: packetVersion({
                  id: "version_2",
                  versionNumber: 2,
                  title: "Second packet",
                }),
                versions: [
                  packetVersion({
                    id: "version_2",
                    versionNumber: 2,
                    title: "Second packet",
                  }),
                ],
              }),
            )
          : packetWorkspaceResponse(workspace());
      }

      expect(request.name).toBe("PacketsStartWorkRunMutation");
      return runStartResponse("run_1", "operation_run_1");
    });

    renderWithRelay(network);
    await screen.findByText("Current version 1");
    fireEvent.click(screen.getByRole("button", { name: "Start work run" }));
    await screen.findByRole("link", { name: /Open run run_1/i });

    fireEvent.click(screen.getByRole("button", { name: /Second packet/i }));

    expect(await screen.findByText("Current version 2")).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Run result" })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /Open run run_1/i })).not.toBeInTheDocument();
  });

  it("starts a new idempotent attempt after a successful run cycle", async () => {
    const idempotencyKeys: string[] = [];
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return packetConnectionResponse([packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return packetWorkspaceResponse(workspace());
      }

      expect(request.name).toBe("PacketsStartWorkRunMutation");
      idempotencyKeys.push(variables.input.idempotencyKey);
      const runNumber = idempotencyKeys.length;
      return runStartResponse(`run_${runNumber}`, `operation_run_${runNumber}`);
    });

    renderWithRelay(network);
    await screen.findByText("Current version 1");
    fireEvent.click(screen.getByRole("button", { name: "Start work run" }));
    await screen.findByRole("link", { name: /Open run run_1/i });

    fireEvent.click(screen.getByRole("button", { name: "Start work run" }));
    await screen.findByRole("link", { name: /Open run run_2/i });

    expect(idempotencyKeys).toHaveLength(2);
    expect(idempotencyKeys[1]).not.toBe(idempotencyKeys[0]);
  });

  it("keeps run start unavailable when the current affordance is disabled", async () => {
    renderWithRelay(
      packetWorkspaceNetwork(
        workspace({
          ready: false,
          status: "blocked",
          blockerReasons: ["missing_success_criteria"],
          allowedNextActions: [],
          commandAffordances: [
            startAffordance({
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
    const nextPage = deferredGraphQLResponse();
    const network = vi.fn(
      async (request, variables): Promise<GraphQLResponse> =>
        request.name === "PacketsWorkspaceDetailQuery"
          ? packetWorkspaceResponse(workspace())
          : variables.after === "cursor_1"
            ? nextPage.promise
            : packetConnectionResponse([packet()], {
                hasNextPage: true,
                endCursor: "cursor_1",
              }),
    );

    renderWithRelay(network);
    await screen.findByRole("button", { name: "Next" });
    await waitFor(() => expect(screen.getByRole("button", { name: "Next" })).toBeEnabled());

    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(screen.getByRole("status")).toHaveTextContent("Loading packet page...");
    expect(screen.queryByRole("button", { name: /First packet/i })).not.toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet detail" })).toHaveTextContent(
      "No packet selected.",
    );
    nextPage.resolve(
      packetConnectionResponse([packet({ id: "packet_2", title: "Second packet" })], {
        hasPreviousPage: true,
        startCursor: "cursor_2",
        endCursor: "cursor_2",
      }),
    );

    await waitFor(() => {
      expect(lastVariablesFor(network, "PacketsRouteQuery")).toEqual({
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
        return packetWorkspaceResponse(workspace());
      }

      if (variables.after === "cursor_1") {
        throw new Error("authorization policy secret_alpha denied packet_9");
      }

      return packetConnectionResponse([packet()], {
        hasNextPage: true,
        endCursor: "cursor_1",
      });
    });

    renderWithRelay(network);
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
      expect(lastVariablesFor(network, "PacketsRouteQuery")).toEqual({
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

  it("bounds the compact packet list while preserving list scrolling", () => {
    const styles = readFileSync(join(process.cwd(), "src/styles/global.css"), "utf8");
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
    const styles = readFileSync(join(process.cwd(), "src/styles/global.css"), "utf8");
    const detailRows = styles.match(/\.packet-detail-list div\s*\{([^}]*)\}/)?.[1] ?? "";

    expect(detailRows).toContain("border-bottom: 1px solid var(--og-color-border);");
    expect(detailRows).not.toContain("#edf1f3");
  });

  it("returns to the previous cursor page", async () => {
    const network = vi.fn(
      async (request, variables): Promise<GraphQLResponse> =>
        request.name === "PacketsWorkspaceDetailQuery"
          ? packetWorkspaceResponse(workspace())
          : variables.after === "cursor_1"
            ? packetConnectionResponse([packet({ id: "packet_2", title: "Second packet" })], {
                hasPreviousPage: true,
                startCursor: "cursor_2",
                endCursor: "cursor_2",
              })
            : packetConnectionResponse([packet()], {
                hasNextPage: true,
                startCursor: "cursor_1",
                endCursor: "cursor_1",
              }),
    );

    renderWithRelay(network);
    await screen.findByRole("button", { name: "Next" });
    await waitFor(() => expect(screen.getByRole("button", { name: "Next" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    await waitFor(() => expect(screen.getByRole("button", { name: "Previous" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Previous" }));

    await waitFor(() => {
      expect(lastVariablesFor(network, "PacketsRouteQuery")).toEqual({
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

function renderWithRelay(network: FetchFunction) {
  const environment = new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(network),
    store: new Store(new RecordSource()),
  });

  return render(
    <MemoryRouter initialEntries={["/packets"]}>
      <RelayEnvironmentProvider environment={environment}>
        <PacketsRoute />
      </RelayEnvironmentProvider>
    </MemoryRouter>,
  );
}

function lastVariablesFor(network: ReturnType<typeof vi.fn>, requestName: string) {
  return [...network.mock.calls].reverse().find(([request]) => request.name === requestName)?.[1];
}

function packetNetwork(
  packets: ReturnType<typeof packet>[],
  createAffordance = createPacketAffordance(),
) {
  return vi.fn(
    async (request): Promise<GraphQLResponse> =>
      request.name === "PacketsWorkspaceDetailQuery"
        ? packetWorkspaceResponse(workspace())
        : packetConnectionResponse(packets, {}, createAffordance),
  );
}

function packetWorkspaceNetwork(detail: ReturnType<typeof workspace>) {
  return vi.fn(
    async (request): Promise<GraphQLResponse> =>
      request.name === "PacketsWorkspaceDetailQuery"
        ? packetWorkspaceResponse(detail)
        : packetConnectionResponse([packet()]),
  );
}

function packetWorkspaceResponse(
  detail: ReturnType<typeof workspace>,
  pageInfo = {
    hasNextPage: false,
    hasPreviousPage: false,
    startCursor: detail.versions[0]?.id ?? null,
    endCursor: detail.versions.at(-1)?.id ?? null,
  },
): GraphQLResponse {
  return {
    data: {
      operatorPacketWorkspace: {
        ...detail,
        versionHistory: {
          edges: detail.versions.map((version, index) => ({
            cursor: `${pageInfo.startCursor ?? "version"}:${index}`,
            node: version,
          })),
          pageInfo,
        },
      },
    },
  };
}

function runStartResponse(runId: string, operationId: string): GraphQLResponse {
  return {
    data: {
      startWorkRun: {
        command: "start_work_run",
        operationId,
        affectedIds: [{ type: "work_run", id: runId }],
        run: {
          id: runId,
          executionState: "pending",
          verificationState: "pending",
        },
        requiredChecks: [
          { id: `required_${runId}`, verificationCheckId: "check_1", state: "pending" },
        ],
      },
    },
  };
}

function workspace(overrides: Partial<WorkspacePayload> = {}): WorkspacePayload {
  return {
    sourceWatermark: "packet-watermark-1",
    ready: true,
    status: "ready_for_run",
    blockerReasons: [],
    allowedNextActions: ["create_work_packet_version", "start_work_run"],
    packet: packetWorkspacePacket(),
    currentVersion: packetVersion(),
    versions: [packetVersion()],
    commandAffordances: [versionAffordance(), startAffordance()],
    ...overrides,
  };
}

function packetWorkspacePacket(overrides: Partial<WorkspacePacketPayload> = {}) {
  return {
    id: "packet_1",
    title: "First packet",
    state: "ready",
    currentVersionId: "version_1",
    operationId: "operation_1",
    ...overrides,
  };
}

function packetVersion(overrides: Partial<WorkspaceVersionPayload> = {}) {
  return {
    id: "version_1",
    versionNumber: 1,
    lifecycleState: "ready",
    title: "First packet",
    objective: "Run selected work",
    contextSummary: "Current packet context",
    requirements: "Preserve immutable history",
    successCriteria: "The required check passes",
    autonomyPosture: "human_supervised",
    sourceGraphItemIds: ["graph_1"],
    verificationCheckIds: ["check_1"],
    operationId: "operation_1",
    insertedAt: "2026-07-09T12:00:00Z",
    ...overrides,
  };
}

function startAffordance(overrides: Partial<CommandAffordancePayload> = {}) {
  return {
    identity: "start_work_run",
    state: "enabled",
    reasonCodes: [],
    blockerReasons: [],
    safeExplanation: "Start a work run from the current packet version.",
    requiredFields: ["packet_version_id", "source_surface", "reason", "authority_posture"],
    inputDefaults: [
      { field: "packet_version_id", value: "version_1", values: [] },
      { field: "source_surface", value: "packet_workspace", values: [] },
      {
        field: "reason",
        value: "Start work from the packet workspace.",
        values: [],
      },
      { field: "authority_posture", value: "human_supervised", values: [] },
    ],
    targetIds: [
      { type: "work_packet", id: "packet_1" },
      { type: "work_packet_version", id: "version_1" },
    ],
    traceLinks: [],
    decisionLinks: [],
    ...overrides,
  };
}

function versionAffordance(overrides: Partial<CommandAffordancePayload> = {}) {
  return {
    identity: "create_work_packet_version",
    state: "enabled",
    reasonCodes: [],
    blockerReasons: [],
    safeExplanation: "Create the next immutable version of this work packet.",
    requiredFields: [],
    inputDefaults: [],
    targetIds: [],
    traceLinks: [],
    decisionLinks: [],
    ...overrides,
  };
}

function createPacketAffordance(overrides: Partial<CommandAffordancePayload> = {}) {
  return {
    identity: "create_work_packet",
    state: "enabled",
    reasonCodes: [],
    blockerReasons: [],
    safeExplanation: "Create a work packet.",
    requiredFields: [],
    inputDefaults: [],
    targetIds: [],
    traceLinks: [],
    decisionLinks: [],
    ...overrides,
  };
}

function packetConnectionResponse(
  packets: ReturnType<typeof packet>[],
  pageInfoOverrides: Partial<PageInfoPayload> = {},
  createAffordance = createPacketAffordance(),
  createdPackets: ReturnType<typeof packet>[] = [],
): GraphQLResponse {
  return {
    data: {
      operatorPacketCreateAffordance: createAffordance,
      createdPacket: {
        edges: createdPackets.map((node, index) => ({
          cursor: `created_cursor_${index + 1}`,
          node,
        })),
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: createdPackets.length > 0 ? "created_cursor_1" : null,
          endCursor: createdPackets.length > 0 ? `created_cursor_${createdPackets.length}` : null,
        },
      },
      listWorkPackets: {
        edges: packets.map((node, index) => ({
          cursor: `cursor_${index + 1}`,
          node,
        })),
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: packets.length > 0 ? "cursor_1" : null,
          endCursor: packets.length > 0 ? `cursor_${packets.length}` : null,
          ...pageInfoOverrides,
        },
      },
    },
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
    ...overrides,
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

type WorkspacePacketPayload = {
  id: string;
  title: string;
  state: string;
  currentVersionId: string;
  operationId: string | null;
};

type WorkspaceVersionPayload = {
  id: string;
  versionNumber: number;
  lifecycleState: string;
  title: string;
  objective: string;
  contextSummary: string;
  requirements: string;
  successCriteria: string;
  autonomyPosture: string;
  sourceGraphItemIds: string[];
  verificationCheckIds: string[];
  operationId: string;
  insertedAt: string;
};

type CommandAffordancePayload = {
  identity: string;
  state: string;
  reasonCodes: string[];
  blockerReasons: string[];
  safeExplanation: string;
  requiredFields: string[];
  inputDefaults: Array<{ field: string; value: string | null; values: string[] }>;
  targetIds: Array<{ type: string; id: string }>;
  traceLinks: Array<{ type: string; id: string }>;
  decisionLinks: Array<{ type: string; id: string }>;
};

type WorkspacePayload = {
  sourceWatermark: string;
  ready: boolean;
  status: string;
  blockerReasons: string[];
  allowedNextActions: string[];
  packet: WorkspacePacketPayload;
  currentVersion: WorkspaceVersionPayload;
  versions: WorkspaceVersionPayload[];
  commandAffordances: CommandAffordancePayload[];
};
