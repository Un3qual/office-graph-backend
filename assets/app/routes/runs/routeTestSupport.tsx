import { render } from "@testing-library/react";
import { RelayEnvironmentProvider } from "react-relay";
import { MemoryRouter, useLocation } from "react-router";
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
import RunsRoute from "./route";

export function renderWithRelay(network: FetchFunction, initialEntry = "/runs") {
  const environment = new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(network),
    store: new Store(new RecordSource()),
  });

  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <RelayEnvironmentProvider environment={environment}>
        <RunsRoute />
        <LocationProbe />
      </RelayEnvironmentProvider>
    </MemoryRouter>,
  );
}

export function createRunsNetwork({
  rows = [runSummary()],
  states = {},
}: {
  rows?: RunSummaryPayload[];
  states?: Record<string, RunStatePayload>;
} = {}) {
  return vi.fn(async (request, variables): Promise<GraphQLResponse> => {
    if (request.name === "RunsRouteQuery") {
      return runsConnectionResponse(rows);
    }

    if (request.name === "RunDetailQuery") {
      return {
        data: {
          operatorRunState:
            states[String(variables.id)] ??
            runState({
              run: {
                id: String(variables.id),
                aggregateState: "running",
                executionState: "completed",
                verificationState: "pending",
              },
            }),
        },
      };
    }

    throw new Error(`Unexpected Relay request in all-runs route test: ${request.name}`);
  });
}

export function runsConnectionResponse(
  rows: RunSummaryPayload[],
  pageInfoOverrides: Partial<PageInfoPayload> = {},
): GraphQLResponse {
  return {
    data: {
      operatorRuns: {
        edges: rows.map((node, index) => ({
          cursor: `run_cursor_${index + 1}`,
          node,
        })),
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: rows.length > 0 ? "run_cursor_1" : null,
          endCursor: rows.length > 0 ? `run_cursor_${rows.length}` : null,
          ...pageInfoOverrides,
        },
      },
    },
  };
}

export function runSummary(overrides: Partial<RunSummaryPayload> = {}): RunSummaryPayload {
  return {
    id: "run_new",
    objective: "Review the newest authorized run",
    aggregateState: "running",
    executionState: "completed",
    verificationState: "pending",
    insertedAt: "2026-07-23T19:00:00Z",
    sourceWatermark: "operation_new",
    packet: { id: "packet_new", title: "Newest packet", state: "active" },
    packetVersion: {
      id: "version_new",
      versionNumber: 3,
      lifecycleState: "active",
      objective: "Review the newest authorized run",
    },
    ...overrides,
  };
}

export function runState(overrides: Partial<RunStatePayload> = {}): RunStatePayload {
  return {
    type: "operator_run_state",
    status: "awaiting_evidence_acceptance",
    sourceWatermark: "operation_new",
    packet: { id: "packet_new", title: "Newest packet", state: "active" },
    packetVersion: {
      id: "version_new",
      versionNumber: 3,
      lifecycleState: "active",
      objective: "Review the newest authorized run",
    },
    run: {
      id: "run_new",
      aggregateState: "running",
      executionState: "completed",
      verificationState: "pending",
    },
    requiredChecks: [
      {
        id: "required_1",
        graphItemId: "graph_1",
        verificationCheckId: "check_1",
        state: "open",
      },
    ],
    evidenceCandidates: [
      {
        id: "candidate_1",
        verificationCheckId: "check_1",
        executionObservationId: "observation_1",
        claim: "Release evidence is ready.",
        state: "candidate",
        freshnessState: "fresh",
        trustBasis: "owner_attested",
        sourceKind: "human",
        sourceIdentity: "manual:release",
      },
    ],
    evidenceItems: [
      {
        id: "evidence_1",
        state: "accepted",
        candidateId: "candidate_1",
        workRunId: "run_new",
      },
    ],
    verificationResults: [
      {
        id: "result_1",
        result: "passed",
        verificationCheckId: "check_1",
        evidenceItemId: "evidence_1",
        operationId: "operation_verify",
        actorPrincipalId: "principal_1",
        policyBasis: "owner_acceptance",
        targetGraphItemId: "graph_1",
        workRunId: "run_new",
        workPacketVersionId: "version_new",
      },
    ],
    missingEvidence: [
      {
        verificationCheckId: "check_2",
        reason: "missing_accepted_evidence",
      },
    ],
    activity: {
      edges: [
        {
          cursor: "activity_cursor_1",
          node: {
            kind: "required_check",
            stableId: "required_1",
            title: "Release verification",
            status: "open",
          },
        },
        {
          cursor: "activity_cursor_2",
          node: {
            kind: "evidence_item",
            stableId: "evidence_1",
            title: "Accepted release evidence",
            status: "accepted",
          },
        },
      ],
      pageInfo: {
        hasNextPage: true,
        hasPreviousPage: false,
        startCursor: "activity_cursor_1",
        endCursor: "activity_cursor_2",
      },
    },
    ...overrides,
  };
}

export function deferredGraphQLResponse() {
  let resolve!: (value: GraphQLResponse) => void;
  let reject!: (reason: Error) => void;
  const promise = new Promise<GraphQLResponse>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });

  return { promise, reject, resolve };
}

export function lastVariablesFor(network: ReturnType<typeof vi.fn>, requestName: string) {
  return [...network.mock.calls].reverse().find(([request]) => request.name === requestName)?.[1];
}

function LocationProbe() {
  const location = useLocation();

  return <output data-testid="route-location">{`${location.pathname}${location.search}`}</output>;
}

type PageInfoPayload = {
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  startCursor: string | null;
  endCursor: string | null;
};

type RunSummaryPayload = {
  id: string;
  objective: string | null;
  aggregateState: string;
  executionState: string;
  verificationState: string;
  insertedAt: string;
  sourceWatermark: string;
  packet: { id: string; title: string; state: string };
  packetVersion: {
    id: string;
    versionNumber: number;
    lifecycleState: string;
    objective: string | null;
  };
};

type RunStatePayload = {
  type: string;
  status: string;
  sourceWatermark: string | null;
  packet: { id: string; title: string; state: string };
  packetVersion: {
    id: string;
    versionNumber: number;
    lifecycleState: string;
    objective: string | null;
  };
  run: {
    id: string;
    aggregateState: string;
    executionState: string;
    verificationState: string;
  };
  requiredChecks: Array<{
    id: string;
    graphItemId: string | null;
    verificationCheckId: string | null;
    state: string;
  }>;
  evidenceCandidates: Array<{
    id: string;
    verificationCheckId: string;
    executionObservationId: string | null;
    claim: string;
    state: string;
    freshnessState: string;
    trustBasis: string;
    sourceKind: string;
    sourceIdentity: string;
  }>;
  evidenceItems: Array<{
    id: string;
    state: string;
    candidateId: string;
    workRunId: string;
  }>;
  verificationResults: Array<{
    id: string;
    result: string;
    verificationCheckId: string;
    evidenceItemId: string;
    operationId: string;
    actorPrincipalId: string;
    policyBasis: string;
    targetGraphItemId: string;
    workRunId: string;
    workPacketVersionId: string;
  }>;
  missingEvidence: Array<{
    verificationCheckId: string;
    reason: string;
  }>;
  activity: {
    edges: Array<{
      cursor: string;
      node: {
        kind: string;
        stableId: string;
        title: string;
        status: string;
      };
    }>;
    pageInfo: PageInfoPayload;
  };
};
