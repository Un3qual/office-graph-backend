import { render } from "@testing-library/react";
import { RelayEnvironmentProvider } from "react-relay";
import { MemoryRouter } from "react-router";
import {
  Environment,
  type FetchFunction,
  type GraphQLResponse,
  Network,
  RecordSource,
  Store,
} from "relay-runtime";
import { vi } from "vitest";
import { getOfficeGraphDataID } from "../../relay/environment";
import PacketsRoute from "./route";

export function renderWithRelay(network: FetchFunction) {
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

export function lastVariablesFor(network: ReturnType<typeof vi.fn>, requestName: string) {
  return [...network.mock.calls].reverse().find(([request]) => request.name === requestName)?.[1];
}

export function packetNetwork(
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

export function packetWorkspaceNetwork(detail: ReturnType<typeof workspace>) {
  return vi.fn(
    async (request): Promise<GraphQLResponse> =>
      request.name === "PacketsWorkspaceDetailQuery"
        ? packetWorkspaceResponse(detail)
        : packetConnectionResponse([packet()]),
  );
}

export function packetWorkspaceResponse(
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

export function runStartResponse(runId: string, operationId: string): GraphQLResponse {
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

export function workspace(overrides: Partial<WorkspacePayload> = {}): WorkspacePayload {
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

export function packetWorkspacePacket(overrides: Partial<WorkspacePacketPayload> = {}) {
  return {
    id: "packet_1",
    title: "First packet",
    state: "ready",
    currentVersionId: "version_1",
    operationId: "operation_1",
    ...overrides,
  };
}

export function packetVersion(overrides: Partial<WorkspaceVersionPayload> = {}) {
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

export function startAffordance(overrides: Partial<CommandAffordancePayload> = {}) {
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

export function versionAffordance(overrides: Partial<CommandAffordancePayload> = {}) {
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

export function createPacketAffordance(overrides: Partial<CommandAffordancePayload> = {}) {
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

export function packetConnectionResponse(
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

export function packet(overrides: Partial<PacketPayload> = {}) {
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

export function deferredGraphQLResponse() {
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
