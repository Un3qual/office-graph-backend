import { vi } from "vitest";
import type { GraphQLFetcher, GraphQLResponse } from "./workflowTypes";

export function createGraphQLTestFetcher(responses: Record<string, unknown>): GraphQLFetcher {
  const fetcher = async ({ query }: Parameters<GraphQLFetcher>[0]): Promise<GraphQLResponse> => {
    if (query.includes("operatorInbox")) {
      return { data: { operatorInbox: responses.operatorInbox } };
    }

    if (query.includes("operatorWorkflowItem")) {
      return { data: { operatorWorkflowItem: responses.operatorWorkflowItem } };
    }

    if (query.includes("operatorPacketReadiness")) {
      return { data: { operatorPacketReadiness: responses.operatorPacketReadiness } };
    }

    if (query.includes("operatorRunState")) {
      return { data: { operatorRunState: responses.operatorRunState } };
    }

    throw new Error("Unexpected GraphQL query in test.");
  };

  return vi.fn(fetcher);
}

export const graphQLInbox = {
  type: "operator_inbox",
  empty: false,
  hasMore: false,
  limit: 50,
  nextOffset: null,
  offset: 0,
  sourceWatermark: "op_123",
  rows: [
    {
      type: "operator_workflow_item",
      typedId: { type: "normalized_intake_event", id: "evt_1" },
      normalizedEventId: "evt_1",
      duplicateOfId: null,
      status: "ready_for_packet",
      reasonCodes: [],
      source: {
        identity: "manual:operator-console",
        replayIdentity: "paste:operator-console",
        outcome: "accepted"
      },
      proposedChangeStatus: { pending: 4, applied: 0, rejected: 0, total: 4 },
      blockerReasons: [],
      allowedNextActions: ["prepare_packet"],
      operationWatermark: "op_123",
      sourceWatermark: "op_123",
      graphLinks: [
        {
          type: "verification_check",
          id: "check_1",
          graphItemId: "graph_1",
          title: "Run console verification",
          state: "required"
        },
        {
          type: "work_run",
          id: "run_1",
          graphItemId: null,
          title: "Console verification run",
          state: "running"
        }
      ],
      graphRelationships: [],
      auditTrace: { operationId: null, resourceCount: 0, resources: [] },
      revisionTrace: { operationId: "operation_1", resourceCount: 2, resources: [] }
    }
  ]
};

export const graphQLRunState = {
  type: "operator_run_state",
  status: "awaiting_evidence_acceptance",
  allowedNextActions: ["accept_evidence"],
  sourceWatermark: "run_1",
  packet: { id: "packet_1", title: "Operator console packet", state: "active" },
  packetVersion: {
    id: "version_1",
    versionNumber: 1,
    lifecycleState: "active",
    objective: "Verify the operator console renders workflow state."
  },
  run: {
    id: "run_1",
    aggregateState: "running",
    executionState: "completed",
    verificationState: "pending"
  },
  requiredChecks: [{ id: "required_1", verificationCheckId: "check_1", state: "open" }],
  observations: [
    {
      id: "observation_1",
      verificationCheckId: "check_1",
      graphItemId: "graph_1",
      normalizedStatus: "succeeded",
      freshnessState: "fresh",
      trustBasis: "owner_attested",
      sourceKind: "human",
      sourceIdentity: "manual:operator-console"
    }
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
      sourceIdentity: "manual:operator-console"
    }
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
      workPacketVersionId: "version_1"
    }
  ],
  missingEvidence: [{ verificationCheckId: "check_1", reason: "missing_accepted_evidence" }]
};
