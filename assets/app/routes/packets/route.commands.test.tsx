import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";

import * as support from "./routeTestSupport";

describe("packet workspace route reads", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("creates a packet, selects it, and starts a new attempt after success", async () => {
    let created = false;
    const idempotencyKeys: string[] = [];
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return support.packetConnectionResponse(
          created
            ? [
                support.packet(),
                support.packet({
                  id: "relay_packet_created",
                  operationId: "operation_created",
                  title: "Created packet",
                }),
              ]
            : [support.packet()],
        );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        if (variables.id !== "relay_packet_created") {
          return support.packetWorkspaceResponse(support.workspace());
        }

        return support.packetWorkspaceResponse(
          support.workspace({
            packet: support.packetWorkspacePacket({
              id: "raw_packet_created",
              title: "Created packet",
              currentVersionId: "version_created",
            }),
            currentVersion: support.packetVersion({
              id: "version_created",
              title: "Created packet",
            }),
            versions: [support.packetVersion({ id: "version_created", title: "Created packet" })],
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

    support.renderWithRelay(network);
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
    const createdPacket = support.packet({
      id: "relay_packet_created",
      operationId: "operation_created",
      title: "Created packet",
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        if (variables.after === "cursor_1") {
          return support.packetConnectionResponse([
            support.packet({ id: "packet_2", title: "Second packet" }),
          ]);
        }

        return support.packetConnectionResponse(
          [support.packet()],
          created ? {} : { hasNextPage: true, endCursor: "cursor_1" },
          support.createPacketAffordance(),
          created ? [createdPacket] : [],
        );
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(support.workspace());
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

    support.renderWithRelay(network);
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
    expect(support.lastVariablesFor(network, "PacketsRouteQuery")).toEqual({
      first: 50,
      after: null,
      createdOperationId: "operation_created",
      loadCreatedPacket: true,
    });
    expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
  });

  it("creates a new version with the exact current id and preserves immutable history", async () => {
    let detail = support.workspace();
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return support.packetConnectionResponse([support.packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(detail);
      }

      expect(request.name).toBe("PacketsCreateWorkPacketVersionMutation");
      expect(variables.input).toMatchObject({
        packetId: "packet_1",
        expectedCurrentVersionId: "version_1",
        title: "Revised packet",
        sourceGraphItemIds: ["graph_1"],
        verificationCheckIds: ["check_1"],
      });

      const versionTwo = support.packetVersion({
        id: "version_2",
        versionNumber: 2,
        title: "Revised packet",
      });
      detail = support.workspace({
        packet: support.packetWorkspacePacket({
          title: "Revised packet",
          currentVersionId: "version_2",
        }),
        currentVersion: versionTwo,
        versions: [support.packetVersion(), versionTwo],
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

    support.renderWithRelay(network);
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

  it("starts a run only from an enabled current affordance and links the returned state", async () => {
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "PacketsRouteQuery") {
        return support.packetConnectionResponse([support.packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(support.workspace());
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

    support.renderWithRelay(network);
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
        return support.packetConnectionResponse([
          support.packet(),
          support.packet({
            id: "packet_2",
            title: "Second packet",
            currentVersionId: "version_2",
          }),
        ]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return variables.id === "packet_2"
          ? support.packetWorkspaceResponse(
              support.workspace({
                packet: support.packetWorkspacePacket({
                  id: "packet_2",
                  title: "Second packet",
                  currentVersionId: "version_2",
                }),
                currentVersion: support.packetVersion({
                  id: "version_2",
                  versionNumber: 2,
                  title: "Second packet",
                }),
                versions: [
                  support.packetVersion({
                    id: "version_2",
                    versionNumber: 2,
                    title: "Second packet",
                  }),
                ],
              }),
            )
          : support.packetWorkspaceResponse(support.workspace());
      }

      expect(request.name).toBe("PacketsStartWorkRunMutation");
      return support.runStartResponse("run_1", "operation_run_1");
    });

    support.renderWithRelay(network);
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
        return support.packetConnectionResponse([support.packet()]);
      }

      if (request.name === "PacketsWorkspaceDetailQuery") {
        return support.packetWorkspaceResponse(support.workspace());
      }

      expect(request.name).toBe("PacketsStartWorkRunMutation");
      idempotencyKeys.push(variables.input.idempotencyKey);
      const runNumber = idempotencyKeys.length;
      return support.runStartResponse(`run_${runNumber}`, `operation_run_${runNumber}`);
    });

    support.renderWithRelay(network);
    await screen.findByText("Current version 1");
    fireEvent.click(screen.getByRole("button", { name: "Start work run" }));
    await screen.findByRole("link", { name: /Open run run_1/i });

    fireEvent.click(screen.getByRole("button", { name: "Start work run" }));
    await screen.findByRole("link", { name: /Open run run_2/i });

    expect(idempotencyKeys).toHaveLength(2);
    expect(idempotencyKeys[1]).not.toBe(idempotencyKeys[0]);
  });
});
