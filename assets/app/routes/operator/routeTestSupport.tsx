import { render } from "@testing-library/react";
import type { ReactElement } from "react";
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

export function operatorCommandNetwork(runState: ReturnType<typeof operatorRunState>) {
  return vi.fn(async (request, variables): Promise<GraphQLResponse> => {
    if (request.name === "OperatorWorkflowRouteQuery") {
      return workflowConnectionResponse([operatorWorkflowItem()], variables);
    }
    if (request.name === "OperatorRunStateQuery") {
      return { data: { operatorRunState: runState } };
    }
    if (request.name.endsWith("Mutation")) {
      return new Promise<GraphQLResponse>(() => undefined);
    }
    throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
  });
}

export function lastVariablesFor(network: ReturnType<typeof vi.fn>, requestName: string) {
  return [...network.mock.calls].reverse().find(([request]) => request.name === requestName)?.[1];
}

export function renderWithRelay(
  ui: ReactElement,
  network: FetchFunction,
  initialEntry = "/operator",
) {
  const environment = new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(withEmptyAgentActivityFallback(network)),
    store: new Store(new RecordSource()),
  });

  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <RelayEnvironmentProvider environment={environment}>{ui}</RelayEnvironmentProvider>
    </MemoryRouter>,
  );
}

function withEmptyAgentActivityFallback(network: FetchFunction): FetchFunction {
  return async (request, variables, cacheConfig, uploadables) => {
    try {
      return await (network(
        request,
        variables,
        cacheConfig,
        uploadables,
      ) as Promise<GraphQLResponse>);
    } catch (error) {
      if (
        request.name !== "OperatorRunConversationQuery" ||
        !(error instanceof Error) ||
        !error.message.startsWith("Unexpected Relay request")
      ) {
        throw error;
      }

      return {
        data: {
          operatorRunConversation: {
            type: "operator_run_conversation",
            sourceWatermark: `${variables.runId}:${variables.graphItemId}:empty`,
            allowedNextActions: [],
            commandAffordances: [],
            conversation: null,
            messages: [],
            executions: [],
            approvalRequests: [],
            contextExpansionRequests: [],
          },
        },
      };
    }
  };
}

export function createOperatorNetwork({
  workflowItems,
  readiness,
  runState,
}: {
  workflowItems: ReturnType<typeof operatorWorkflowItem>[] | null;
  readiness?: ReturnType<typeof operatorPacketReadiness>;
  runState?: ReturnType<typeof operatorRunState>;
}) {
  return vi.fn(async (request, variables): Promise<GraphQLResponse> => {
    if (request.name === "OperatorWorkflowRouteQuery") {
      return workflowConnectionResponse(workflowItems, variables);
    }

    if (request.name === "OperatorPacketReadinessQuery") {
      return {
        data: {
          operatorPacketReadiness: readiness ?? operatorPacketReadiness(),
        },
      };
    }

    if (request.name === "OperatorRunStateQuery") {
      return {
        data: {
          operatorRunState: runState ?? operatorRunState(),
        },
      };
    }

    throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
  });
}

export function workflowConnectionResponse(
  workflowItems: ReturnType<typeof operatorWorkflowItem>[] | null,
  variables: Readonly<Record<string, unknown>>,
  pageInfoOverrides: Partial<OperatorWorkflowPageInfoPayload> = {},
  manualIntakeAffordance: CommandAffordancePayload = enabledCommandAffordance(
    "submit_manual_intake",
  ),
): GraphQLResponse {
  if (workflowItems === null) {
    return {
      data: {
        operatorManualIntakeAffordance: manualIntakeAffordance,
        operatorWorkflowItems: null,
      },
    };
  }

  return {
    data: {
      operatorManualIntakeAffordance: manualIntakeAffordance,
      operatorWorkflowItems: {
        edges: workflowItems.map((node, index) => ({
          cursor: `cursor_${index + 1}`,
          node,
        })),
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: Boolean(variables.after),
          startCursor: workflowItems.length > 0 ? "cursor_1" : null,
          endCursor: workflowItems.length > 0 ? `cursor_${workflowItems.length}` : null,
          ...pageInfoOverrides,
        },
      },
    },
  };
}

export function deferredGraphQLResponse() {
  let resolve!: (value: GraphQLResponse) => void;
  const promise = new Promise<GraphQLResponse>((resolvePromise) => {
    resolve = resolvePromise;
  });

  return { promise, resolve };
}

export function operatorWorkflowItem(overrides: Partial<OperatorWorkflowItemPayload> = {}) {
  const title = overrides.title ?? overrides.normalizedEventId ?? "evt_1";
  const graphLinks = overrides.graphLinks ?? [
    {
      type: "verification_check",
      id: "check_1",
      graphItemId: "graph_1",
      title: "Run console verification",
      state: "required",
    },
    {
      type: "work_run",
      id: "run_1",
      graphItemId: null,
      title: "Console verification run",
      state: "running",
    },
  ];
  const commandAffordances = overrides.commandAffordances ?? [
    preparePacketCommandForGraphLinks(graphLinks),
  ];

  return {
    __typename: "OperatorWorkflowItem",
    id: "operator_workflow_item_global_1",
    type: "operator_workflow_item",
    typedId: { type: "normalized_intake_event", id: "evt_1" },
    normalizedEventId: "evt_1",
    duplicateOfId: null,
    title,
    sourceSummary: `manual:operator-console · ${title}`,
    proposedActionPreviews: [
      { action: "create_signal", title: "Run console verification", status: "pending" },
    ],
    status: "ready_for_packet",
    reasonCodes: [],
    source: {
      identity: "manual:operator-console",
      replayIdentity: "paste:operator-console",
      outcome: "accepted",
    },
    proposedChangeStatus: { pending: 4, applied: 0, rejected: 0, total: 4 },
    blockerReasons: [],
    allowedNextActions: ["create_work_packet"],
    commandAffordances,
    operationWatermark: "op_123",
    sourceWatermark: "op_123",
    graphLinks,
    graphRelationships: [],
    relationshipSummary: {
      graphLinks: graphLinks.length,
      graphRelationships: 0,
      hasMore: false,
    },
    auditTrace: { operationId: null, resourceCount: 0, resources: [] },
    revisionTrace: { operationId: "operation_1", resourceCount: 2, resources: [] },
    ...overrides,
  };
}

export function preparePacketCommandForGraphLinks(
  graphLinks: OperatorWorkflowItemPayload["graphLinks"],
): CommandAffordancePayload {
  const verificationCheck = graphLinks.find((link) => link.type === "verification_check");
  const title = verificationCheck?.title ?? "Run console verification";
  const sourceGraphItemIds = graphLinks.flatMap((link) =>
    link.graphItemId && link.type !== "work_run" ? [link.graphItemId] : [],
  );
  const verificationCheckIds = graphLinks
    .filter((link) => link.type === "verification_check")
    .map((link) => link.id);

  return {
    identity: "create_work_packet",
    state: "enabled",
    reasonCodes: [],
    blockerReasons: [],
    safeExplanation: "Prepare a work packet from the applied intake.",
    requiredFields: [
      "title",
      "objective",
      "context_summary",
      "requirements",
      "success_criteria",
      "autonomy_posture",
      "source_graph_item_ids",
      "verification_check_ids",
    ],
    inputDefaults: [
      { field: "title", value: title, values: [] },
      { field: "objective", value: title, values: [] },
      { field: "context_summary", value: title, values: [] },
      { field: "requirements", value: title, values: [] },
      { field: "success_criteria", value: title, values: [] },
      { field: "autonomy_posture", value: "human_supervised", values: [] },
      { field: "source_graph_item_ids", value: null, values: sourceGraphItemIds },
      { field: "verification_check_ids", value: null, values: verificationCheckIds },
      {
        field: "primary_source_graph_item_id",
        value: verificationCheck?.graphItemId ?? null,
        values: [],
      },
      { field: "primary_verification_check_id", value: verificationCheck?.id ?? null, values: [] },
    ],
    targetIds: verificationCheck ? [{ type: "verification_check", id: verificationCheck.id }] : [],
    traceLinks: [],
    decisionLinks: [],
  };
}

export function enabledCommandAffordance(
  identity: string,
  inputDefaults: CommandAffordancePayload["inputDefaults"] = [],
  targetIds: CommandAffordancePayload["targetIds"] = [],
): CommandAffordancePayload {
  return {
    identity,
    state: "enabled",
    reasonCodes: [],
    blockerReasons: [],
    safeExplanation: `${identity} is available.`,
    requiredFields: [],
    inputDefaults,
    targetIds,
    traceLinks: [],
    decisionLinks: [],
  };
}

export function operatorPacketReadiness(overrides: Partial<OperatorPacketReadinessPayload> = {}) {
  return {
    type: "packet_readiness",
    ready: true,
    status: "packet_ready",
    allowedNextActions: ["create_work_packet"],
    commandAffordances: [
      {
        identity: "create_work_packet",
        state: "enabled",
        reasonCodes: [],
        blockerReasons: [],
        safeExplanation: "Create a work packet from the selected sources and checks.",
        requiredFields: [],
        inputDefaults: [],
        targetIds: [],
        traceLinks: [],
        decisionLinks: [],
      },
    ],
    blockerReasons: [],
    sourceLinks: [
      {
        type: "verification_check",
        id: "check_1",
        graphItemId: "graph_1",
        title: "Run console verification",
      },
    ],
    requiredChecks: [{ id: "check_1", graphItemId: "graph_1", state: "required" }],
    sourceWatermark: "op_123",
    ...overrides,
  };
}

export function operatorRunState(overrides: Partial<OperatorRunStatePayload> = {}) {
  const state = {
    type: "operator_run_state",
    status: "awaiting_evidence_acceptance",
    allowedNextActions: ["accept_evidence"],
    commandAffordances: [
      {
        identity: "accept_evidence",
        state: "enabled",
        reasonCodes: [],
        blockerReasons: [],
        safeExplanation: "Accept a candidate as evidence for a missing check.",
        requiredFields: [],
        inputDefaults: [],
        targetIds: [{ type: "evidence_candidate", id: "candidate_1" }],
        traceLinks: [],
        decisionLinks: [],
      },
    ],
    commandOptions: {
      observation: [observationCommandOption()],
      evidenceCandidate: [evidenceCandidateCommandOption()],
      evidenceAcceptance: [
        {
          key: "candidate_1",
          label: "Run console verification",
          evidenceCandidateId: "candidate_1",
          result: "passed",
          acceptancePolicyBasis: "owner_acceptance",
        },
      ],
      waiver: [
        {
          key: "required_1",
          label: "Run console verification",
          runId: "run_1",
          runRequiredCheckId: "required_1",
          expectedExecutionState: "completed",
          expectedVerificationState: "pending",
          policyBasis: "owner_exception",
        },
      ],
    },
    commandOptionsOverflow: false,
    commandOptionSummary: {
      observation: 1,
      evidenceCandidate: 1,
      evidenceAcceptance: 1,
      waiver: 1,
    },
    childSummary: {
      requiredChecks: 1,
      observations: 1,
      evidenceCandidates: 1,
      evidenceItems: 0,
      verificationResults: 1,
      missingEvidence: 1,
      hasMore: false,
    },
    activity: {
      edges: [
        {
          cursor: "activity_cursor_1",
          node: {
            kind: "required_check",
            stableId: "required_1",
            title: "Run console verification",
            status: "open",
          },
        },
      ],
      pageInfo: {
        hasNextPage: false,
        hasPreviousPage: false,
        startCursor: "activity_cursor_1",
        endCursor: "activity_cursor_1",
      },
    },
    sourceWatermark: "run_1",
    packet: { id: "packet_1", title: "Operator console packet", state: "active" },
    packetVersion: {
      id: "version_1",
      versionNumber: 1,
      lifecycleState: "active",
      objective: "Verify the operator console renders workflow state.",
    },
    run: {
      id: "run_1",
      aggregateState: "running",
      executionState: "completed",
      verificationState: "pending",
    },
    requiredChecks: [
      { id: "required_1", graphItemId: "graph_1", verificationCheckId: "check_1", state: "open" },
    ],
    observations: [
      {
        id: "observation_1",
        verificationCheckId: "check_1",
        graphItemId: "graph_1",
        normalizedStatus: "succeeded",
        freshnessState: "fresh",
        trustBasis: "owner_attested",
        sourceKind: "human",
        sourceIdentity: "manual:operator-console",
      },
    ],
    evidenceCandidates: [
      {
        id: "candidate_1",
        verificationCheckId: "check_1",
        executionObservationId: "observation_1",
        claim: "Operator console evidence is ready.",
        state: "candidate",
        freshnessState: "fresh",
        trustBasis: "owner_attested",
        sourceKind: "human",
        sourceIdentity: "manual:operator-console",
      },
    ],
    evidenceItems: [],
    verificationResults: [
      {
        id: "result_1",
        result: "passed",
        verificationCheckId: "check_1",
        evidenceItemId: "evidence_1",
        operationId: "operation_1",
        actorPrincipalId: "principal_1",
        policyBasis: "owner_acceptance",
        targetGraphItemId: "graph_1",
        workRunId: "run_1",
        workPacketVersionId: "version_1",
      },
    ],
    missingEvidence: [{ verificationCheckId: "check_1", reason: "missing_accepted_evidence" }],
    ...overrides,
  };

  if (overrides.commandOptions) {
    return state;
  }

  return {
    ...state,
    commandOptions: {
      observation: state.requiredChecks.flatMap((check) =>
        check.verificationCheckId && check.graphItemId
          ? [
              observationCommandOption({
                key: check.id,
                label: check.verificationCheckId,
                verificationCheckId: check.verificationCheckId,
                sourceGraphItemId: check.graphItemId,
              }),
            ]
          : [],
      ),
      evidenceCandidate: state.observations.flatMap((observation) =>
        observation.verificationCheckId
          ? [
              evidenceCandidateCommandOption({
                key: observation.id,
                label: observation.id,
                verificationCheckId: observation.verificationCheckId,
                executionObservationId: observation.id,
                sourceKind: observation.sourceKind,
                sourceIdentity: observation.sourceIdentity,
                freshnessState: observation.freshnessState,
                trustBasis: observation.trustBasis,
              }),
            ]
          : [],
      ),
      evidenceAcceptance: state.evidenceCandidates.map((candidate) => ({
        key: candidate.id,
        label: candidate.claim,
        evidenceCandidateId: candidate.id,
        result: "passed",
        acceptancePolicyBasis: "owner_acceptance",
      })),
      waiver: state.requiredChecks.map((check) => ({
        key: check.id,
        label: check.verificationCheckId ?? check.id,
        runId: state.run.id,
        runRequiredCheckId: check.id,
        expectedExecutionState: state.run.executionState,
        expectedVerificationState: state.run.verificationState,
        policyBasis: "owner_exception",
      })),
    },
  };
}

export function observationCommandOption(overrides: Partial<ObservationCommandOptionPayload> = {}) {
  return {
    key: "required_1",
    label: "Run console verification",
    runId: "run_1",
    verificationCheckId: "check_1",
    sourceGraphItemId: "graph_1",
    observationSourceKind: "human",
    observationSourceIdentity: "operator-console",
    freshnessState: "fresh",
    trustBasis: "owner_attested",
    defaultOutcomeKey: "succeeded",
    outcomes: [
      {
        key: "succeeded",
        label: "Succeeded",
        observedStatus: "succeeded",
        normalizedStatus: "succeeded",
      },
      {
        key: "failed",
        label: "Failed",
        observedStatus: "failed",
        normalizedStatus: "failed",
      },
    ],
    ...overrides,
  };
}

export function evidenceCandidateCommandOption(
  overrides: Partial<EvidenceCandidateCommandOptionPayload> = {},
) {
  return {
    key: "observation_1",
    label: "Run console verification",
    workRunId: "run_1",
    verificationCheckId: "check_1",
    executionObservationId: "observation_1",
    sourceKind: "human",
    sourceIdentity: "manual:operator-console",
    freshnessState: "fresh",
    trustBasis: "owner_attested",
    sensitivity: "internal",
    ...overrides,
  };
}

type OperatorWorkflowItemPayload = {
  id: string;
  status: string;
  normalizedEventId: string;
  title: string;
  sourceSummary: string;
  proposedActionPreviews: Array<{ action: string; title: string; status: string }>;
  typedId: { type: string; id: string };
  allowedNextActions: string[];
  commandAffordances: CommandAffordancePayload[];
  source: { identity: string; replayIdentity: string; outcome: string };
  graphLinks: Array<{
    type: string;
    id: string;
    graphItemId: string | null;
    title: string;
    state: string | null;
  }>;
  graphRelationships: Array<{
    id: string;
    sourceGraphItemId: string;
    targetGraphItemId: string;
    definitionKey: string;
  }>;
  relationshipSummary: {
    graphLinks: number;
    graphRelationships: number;
    hasMore: boolean;
  };
};

type OperatorWorkflowPageInfoPayload = {
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  startCursor: string | null;
  endCursor: string | null;
};

type OperatorPacketReadinessPayload = {
  allowedNextActions: string[];
  commandAffordances: CommandAffordancePayload[];
  status: string;
  sourceLinks: Array<{ type: string; id: string; graphItemId: string; title: string }>;
  requiredChecks: Array<{ id: string; graphItemId: string; state: string }>;
};

type OperatorRunStatePayload = {
  allowedNextActions: string[];
  commandAffordances: CommandAffordancePayload[];
  commandOptions: {
    observation: ObservationCommandOptionPayload[];
    evidenceCandidate: EvidenceCandidateCommandOptionPayload[];
    evidenceAcceptance: Array<{
      key: string;
      label: string;
      evidenceCandidateId: string;
      result: string;
      acceptancePolicyBasis: string;
    }>;
    waiver: Array<{
      key: string;
      label: string;
      runId: string;
      runRequiredCheckId: string;
      expectedExecutionState: string;
      expectedVerificationState: string;
      policyBasis: string;
    }>;
  };
  commandOptionsOverflow: boolean;
  commandOptionSummary: {
    observation: number;
    evidenceCandidate: number;
    evidenceAcceptance: number;
    waiver: number;
  };
  childSummary: {
    requiredChecks: number;
    observations: number;
    evidenceCandidates: number;
    evidenceItems: number;
    verificationResults: number;
    missingEvidence: number;
    hasMore: boolean;
  };
  activity: {
    edges: Array<{
      cursor: string;
      node: { kind: string; stableId: string; title: string; status: string };
    }>;
    pageInfo: OperatorWorkflowPageInfoPayload;
  };
  requiredChecks: Array<{
    id: string;
    graphItemId: string | null;
    verificationCheckId: string | null;
    state: string;
  }>;
  observations: Array<{
    id: string;
    verificationCheckId: string | null;
    graphItemId: string | null;
    normalizedStatus: string;
    freshnessState: string;
    trustBasis: string;
    sourceKind: string;
    sourceIdentity: string;
  }>;
  status: string;
};

type ObservationCommandOptionPayload = {
  key: string;
  label: string;
  runId: string;
  verificationCheckId: string;
  sourceGraphItemId: string;
  observationSourceKind: string;
  observationSourceIdentity: string;
  freshnessState: string;
  trustBasis: string;
  defaultOutcomeKey: string;
  outcomes: Array<{
    key: string;
    label: string;
    observedStatus: string;
    normalizedStatus: string;
  }>;
};

type EvidenceCandidateCommandOptionPayload = {
  key: string;
  label: string;
  workRunId: string;
  verificationCheckId: string;
  executionObservationId: string;
  sourceKind: string;
  sourceIdentity: string;
  freshnessState: string;
  trustBasis: string;
  sensitivity: string;
};

export type CommandAffordancePayload = {
  identity: string;
  state: string;
  reasonCodes: string[];
  blockerReasons: string[];
  safeExplanation: string;
  requiredFields: string[];
  inputDefaults: Array<{ field: string; value: string | null; values: string[] }>;
  targetIds: Array<{ type: string; id: string }>;
  traceLinks: Array<unknown>;
  decisionLinks: Array<unknown>;
};
