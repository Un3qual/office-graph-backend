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
import type { RunActivityFragment$data } from "../../relay/__generated__/RunActivityFragment.graphql";
import type { RunDetailQuery as RunDetailOperation } from "../../relay/__generated__/RunDetailQuery.graphql";
import type { RunsRouteQuery as RunsRouteOperation } from "../../relay/__generated__/RunsRouteQuery.graphql";
import { getOfficeGraphDataID } from "../../relay/environment";
import RunsRoute from "./route";

export function renderWithRelay(network: FetchFunction, initialEntry = "/runs") {
  return renderWithRelayEnvironment(createRelayTestEnvironment(network), initialEntry);
}

export function createRelayTestEnvironment(network: FetchFunction) {
  return new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(network),
    store: new Store(new RecordSource()),
  });
}

export function clearRelayTestEnvironment(environment: Environment) {
  const source = new RecordSource();

  for (const id of environment.getStore().getSource().getRecordIDs()) {
    source.delete(id);
  }

  environment.getStore().publish(source);
  environment.getStore().notify();
}

export function renderWithRelayEnvironment(environment: Environment, initialEntry = "/runs") {
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

export function activityPageResponse({ title }: { title: string }): GraphQLResponse {
  return {
    data: {
      operatorRunState: {
        activity: {
          edges: [
            {
              cursor: "activity_cursor_3",
              node: {
                __typename: "OperatorRunActivity",
                kind: "observation",
                stableId: "observation_3",
                title,
                status: "succeeded",
              },
            },
          ],
          pageInfo: {
            hasNextPage: false,
            hasPreviousPage: true,
            startCursor: "activity_cursor_3",
            endCursor: "activity_cursor_3",
          },
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
    packet: {
      id: "123e4567-e89b-12d3-a456-426614174000",
      title: "Newest packet",
    },
    ...overrides,
  };
}

export function runState(overrides: Partial<RunStatePayload> = {}): RunStatePayload {
  return {
    status: "awaiting_evidence_acceptance",
    packet: {
      id: "123e4567-e89b-12d3-a456-426614174000",
      relayId: "d29ya19wYWNrZXQ6MTIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDAw",
      title: "Newest packet",
    },
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
        verificationCheckId: "check_1",
        state: "open",
      },
    ],
    evidenceCandidates: [
      {
        id: "candidate_1",
        claim: "Release evidence is ready.",
        state: "candidate",
      },
    ],
    evidenceItems: [
      {
        id: "evidence_1",
        state: "accepted",
      },
    ],
    verificationResults: [
      {
        id: "result_1",
        result: "passed",
        verificationCheckId: "check_1",
        policyBasis: "owner_acceptance",
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
            __typename: "OperatorRunActivity",
            kind: "required_check",
            stableId: "required_1",
            title: "Release verification",
            status: "open",
          },
        },
        {
          cursor: "activity_cursor_2",
          node: {
            __typename: "OperatorRunActivity",
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

type RunsConnectionPayload = NonNullable<RunsRouteOperation["response"]["operatorRuns"]>;
type RunSummaryReaderPayload = NonNullable<
  NonNullable<NonNullable<RunsConnectionPayload["edges"]>[number]>["node"]
>;
type RunSummaryPayload = Omit<RunSummaryReaderPayload, "packet"> & {
  packet: RunSummaryReaderPayload["packet"] & { id: string };
};
type PageInfoPayload = RunsConnectionPayload["pageInfo"] & {
  hasPreviousPage: boolean;
  startCursor: string | null;
};
type RunDetailReaderPayload = NonNullable<RunDetailOperation["response"]["operatorRunState"]>;
type RunDetailPayload = Omit<RunDetailReaderPayload, "packet" | "packetVersion"> & {
  packet: RunDetailReaderPayload["packet"] & { id: string };
  packetVersion: (NonNullable<RunDetailReaderPayload["packetVersion"]> & { id: string }) | null;
};
type ActivityPayload = NonNullable<RunActivityFragment$data["operatorRunState"]["activity"]>;
type ActivityEdgePayload = NonNullable<NonNullable<ActivityPayload["edges"]>[number]>;
type ActivityNodePayload = NonNullable<ActivityEdgePayload["node"]>;
type ActivityNetworkPayload = Omit<ActivityPayload, "edges" | "pageInfo"> & {
  edges: Array<{
    cursor: string;
    node: ActivityNodePayload & { __typename: "OperatorRunActivity" };
  }>;
  pageInfo: ActivityPayload["pageInfo"] & {
    hasPreviousPage: boolean;
    startCursor: string | null;
  };
};
type RunStatePayload = RunDetailPayload & { activity: ActivityNetworkPayload };
