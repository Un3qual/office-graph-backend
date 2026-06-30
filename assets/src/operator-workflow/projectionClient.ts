import {
  createOperatorWorkflowApi,
  type OperatorEvidenceCandidate,
  type OperatorEvidenceItem,
  type OperatorInbox,
  type OperatorMissingEvidence,
  type OperatorObservation,
  type OperatorRunState,
  type OperatorVerificationResult,
  type OperatorWorkflowApi,
  type OperatorWorkflowItem,
  type PacketReadiness,
  type PacketReadinessInput,
  type VerificationOutcome
} from "./api";

type GraphQLFetcher = (request: {
  query: string;
  variables: Record<string, unknown>;
}) => Promise<GraphQLResponse>;

type GraphQLResponse = {
  data?: Record<string, unknown>;
  errors?: Array<{ message?: string }>;
};

export type OperatorWorkflowProjectionClient = {
  loadInbox: () => Promise<OperatorInbox>;
  loadItem: (normalizedEventId: string) => Promise<OperatorWorkflowItem>;
  loadPacketReadinessForItem: (item: OperatorWorkflowItem) => Promise<PacketReadiness>;
  loadRunStateForItem: (item: OperatorWorkflowItem) => Promise<OperatorRunState | null>;
  loadVerificationOutcomeForItem: (
    item: OperatorWorkflowItem
  ) => Promise<VerificationOutcome | null>;
};

export function createDefaultOperatorWorkflowProjectionClient() {
  return createJsonOperatorWorkflowProjectionClient(createOperatorWorkflowApi());
}

// Temporary migration bridge: the product frontend should move to GraphQL
// projections, but the current JSON routes remain useful while the console is
// being decomposed.
export function createJsonOperatorWorkflowProjectionClient(
  api: OperatorWorkflowApi
): OperatorWorkflowProjectionClient {
  return {
    loadInbox: api.loadInbox,
    loadItem: api.loadItem,
    loadPacketReadinessForItem: (item) => api.loadPacketReadiness(packetReadinessInputForItem(item)),
    loadRunStateForItem: (item) => {
      const runId = runIdForItem(item);

      return runId ? api.loadRunState(runId) : Promise.resolve(null);
    },
    loadVerificationOutcomeForItem: (item) => {
      const runId = runIdForItem(item);

      return runId ? api.loadVerificationOutcome(runId) : Promise.resolve(null);
    }
  };
}

export function createGraphQLOperatorWorkflowProjectionClient({
  fetcher
}: {
  fetcher: GraphQLFetcher;
}): OperatorWorkflowProjectionClient {
  return {
    loadInbox: async () => {
      const data = await requestGraphQL(fetcher, operatorInboxQuery, {});

      return graphQLInbox(data.operatorInbox);
    },
    loadItem: async (normalizedEventId) => {
      const data = await requestGraphQL(fetcher, operatorWorkflowItemQuery, {
        id: normalizedEventId
      });

      return graphQLItem(data.operatorWorkflowItem);
    },
    loadPacketReadinessForItem: async (item) => {
      const data = await requestGraphQL(fetcher, operatorPacketReadinessQuery, {
        input: graphQLPacketReadinessInput(packetReadinessInputForItem(item))
      });

      return graphQLPacketReadiness(data.operatorPacketReadiness);
    },
    loadRunStateForItem: async (item) => {
      const runId = runIdForItem(item);

      if (!runId) {
        return null;
      }

      const data = await requestGraphQL(fetcher, operatorRunStateQuery, { id: runId });

      return graphQLRunState(data.operatorRunState);
    },
    loadVerificationOutcomeForItem: async (item) => {
      const runId = runIdForItem(item);

      if (!runId) {
        return null;
      }

      const data = await requestGraphQL(fetcher, operatorVerificationOutcomeQuery, { id: runId });

      return graphQLVerificationOutcome(data.operatorVerificationOutcome);
    }
  };
}

export function packetReadinessInputForItem(item: OperatorWorkflowItem): PacketReadinessInput {
  const sourceLinks = item.graph_links.filter(
    (link) => link.graph_item_id && link.type !== "work_run"
  );
  const verificationChecks = item.graph_links.filter((link) => link.type === "verification_check");

  return {
    source_graph_item_ids: sourceLinks.flatMap((link) =>
      link.graph_item_id ? [link.graph_item_id] : []
    ),
    verification_check_ids: verificationChecks.map((link) => link.id)
  };
}

export function runIdForItem(item: OperatorWorkflowItem) {
  return item.graph_links.find((link) => link.type === "work_run")?.id ?? null;
}

async function requestGraphQL(
  fetcher: GraphQLFetcher,
  query: string,
  variables: Record<string, unknown>
) {
  const response = await fetcher({ query, variables });

  if (response.errors?.length) {
    throw new Error(response.errors[0]?.message ?? "The GraphQL projection request failed.");
  }

  if (!response.data) {
    throw new Error("The GraphQL projection response did not include data.");
  }

  return response.data;
}

function graphQLInbox(value: unknown): OperatorInbox {
  const inbox = record(value);

  return {
    type: "operator_inbox",
    empty: booleanValue(inbox.empty),
    source_watermark: nullableString(inbox.sourceWatermark),
    rows: arrayValue(inbox.rows).map(graphQLItem)
  };
}

function graphQLItem(value: unknown): OperatorWorkflowItem {
  const item = record(value);
  const typedId = record(item.typedId);
  const source = record(item.source);
  const proposed = record(item.proposedChangeStatus);

  return {
    type: "operator_workflow_item",
    typed_id: {
      type: stringValue(typedId.type),
      id: stringValue(typedId.id)
    },
    normalized_event_id: stringValue(item.normalizedEventId),
    duplicate_of_id: nullableString(item.duplicateOfId),
    status: stringValue(item.status),
    reason_codes: stringArray(item.reasonCodes),
    source: {
      identity: stringValue(source.identity),
      replay_identity: stringValue(source.replayIdentity),
      outcome: stringValue(source.outcome)
    },
    proposed_change_status: {
      pending: numberValue(proposed.pending),
      applied: numberValue(proposed.applied),
      rejected: numberValue(proposed.rejected),
      total: numberValue(proposed.total)
    },
    blocker_reasons: stringArray(item.blockerReasons),
    allowed_next_actions: stringArray(item.allowedNextActions),
    operation_watermark: nullableString(item.operationWatermark),
    source_watermark: nullableString(item.sourceWatermark),
    graph_links: arrayValue(item.graphLinks).map((link) => {
      const row = record(link);

      return {
        type: stringValue(row.type),
        id: stringValue(row.id),
        graph_item_id: nullableString(row.graphItemId),
        title: stringValue(row.title),
        state: nullableString(row.state)
      };
    }),
    graph_relationships: arrayValue(item.graphRelationships).map((relationship) => {
      const row = record(relationship);

      return {
        id: stringValue(row.id),
        source_graph_item_id: stringValue(row.sourceGraphItemId),
        target_graph_item_id: stringValue(row.targetGraphItemId),
        relationship_type: stringValue(row.relationshipType)
      };
    }),
    audit_trace: graphQLTrace(item.auditTrace),
    revision_trace: graphQLTrace(item.revisionTrace)
  };
}

function graphQLTrace(value: unknown) {
  const trace = record(value);

  return {
    operation_id: nullableString(trace.operationId),
    resource_count: numberValue(trace.resourceCount),
    resources: arrayValue(trace.resources).map((resource) => {
      const row = record(resource);

      return {
        type: stringValue(row.type),
        id: stringValue(row.id)
      };
    })
  };
}

function graphQLPacketReadiness(value: unknown): PacketReadiness {
  const readiness = record(value);

  return {
    type: "packet_readiness",
    ready: booleanValue(readiness.ready),
    status: stringValue(readiness.status),
    allowed_next_actions: stringArray(readiness.allowedNextActions),
    blocker_reasons: stringArray(readiness.blockerReasons),
    source_links: arrayValue(readiness.sourceLinks).map((link) => {
      const row = record(link);

      return {
        type: stringValue(row.type),
        id: stringValue(row.id),
        graph_item_id: stringValue(row.graphItemId),
        title: stringValue(row.title)
      };
    }),
    required_checks: arrayValue(readiness.requiredChecks).map((check) => {
      const row = record(check);

      return {
        id: stringValue(row.id),
        graph_item_id: stringValue(row.graphItemId),
        state: stringValue(row.state)
      };
    }),
    source_watermark: nullableString(readiness.sourceWatermark)
  };
}

function graphQLRunState(value: unknown): OperatorRunState {
  const runState = record(value);
  const packet = record(runState.packet);
  const packetVersion = record(runState.packetVersion);
  const run = record(runState.run);

  return {
    type: "operator_run_state",
    status: stringValue(runState.status),
    allowed_next_actions: stringArray(runState.allowedNextActions),
    source_watermark: nullableString(runState.sourceWatermark),
    packet: {
      id: stringValue(packet.id),
      title: stringValue(packet.title),
      state: stringValue(packet.state)
    },
    packet_version: {
      id: stringValue(packetVersion.id),
      version_number: numberValue(packetVersion.versionNumber),
      lifecycle_state: stringValue(packetVersion.lifecycleState),
      objective: stringValue(packetVersion.objective)
    },
    run: graphQLRunRef(run),
    required_checks: arrayValue(runState.requiredChecks).map(graphQLRequiredCheck),
    observations: arrayValue(runState.observations).map(graphQLObservation),
    evidence_candidates: arrayValue(runState.evidenceCandidates).map(graphQLEvidenceCandidate),
    evidence_items: arrayValue(runState.evidenceItems).map(graphQLEvidenceItem),
    verification_results: arrayValue(runState.verificationResults).map(graphQLVerificationResult),
    missing_evidence: arrayValue(runState.missingEvidence).map(graphQLMissingEvidence)
  };
}

function graphQLVerificationOutcome(value: unknown): VerificationOutcome {
  const outcome = record(value);

  return {
    type: "verification_outcome",
    status: stringValue(outcome.status),
    source_watermark: nullableString(outcome.sourceWatermark),
    run: graphQLRunRef(outcome.run),
    verification_results: arrayValue(outcome.verificationResults).map(graphQLVerificationResult),
    missing_evidence: arrayValue(outcome.missingEvidence).map(graphQLMissingEvidence)
  };
}

function graphQLRunRef(value: unknown) {
  const run = record(value);

  return {
    id: stringValue(run.id),
    aggregate_state: stringValue(run.aggregateState),
    execution_state: stringValue(run.executionState),
    verification_state: stringValue(run.verificationState)
  };
}

function graphQLRequiredCheck(value: unknown) {
  const check = record(value);

  return {
    id: stringValue(check.id),
    verification_check_id: stringValue(check.verificationCheckId),
    state: stringValue(check.state)
  };
}

function graphQLObservation(value: unknown): OperatorObservation {
  const observation = record(value);

  return {
    id: stringValue(observation.id),
    verification_check_id: stringValue(observation.verificationCheckId),
    graph_item_id: nullableString(observation.graphItemId),
    normalized_status: stringValue(observation.normalizedStatus),
    freshness_state: stringValue(observation.freshnessState),
    trust_basis: stringValue(observation.trustBasis),
    source_kind: stringValue(observation.sourceKind),
    source_identity: stringValue(observation.sourceIdentity)
  };
}

function graphQLEvidenceCandidate(value: unknown): OperatorEvidenceCandidate {
  const candidate = record(value);

  return {
    id: stringValue(candidate.id),
    verification_check_id: stringValue(candidate.verificationCheckId),
    execution_observation_id: nullableString(candidate.executionObservationId),
    claim: stringValue(candidate.claim),
    state: stringValue(candidate.state),
    freshness_state: stringValue(candidate.freshnessState),
    trust_basis: stringValue(candidate.trustBasis),
    source_kind: stringValue(candidate.sourceKind),
    source_identity: stringValue(candidate.sourceIdentity)
  };
}

function graphQLEvidenceItem(value: unknown): OperatorEvidenceItem {
  const item = record(value);

  return {
    id: stringValue(item.id),
    state: stringValue(item.state),
    candidate_id: nullableString(item.candidateId),
    work_run_id: nullableString(item.workRunId)
  };
}

function graphQLVerificationResult(value: unknown): OperatorVerificationResult {
  const result = record(value);

  return {
    id: stringValue(result.id),
    result: stringValue(result.result),
    verification_check_id: stringValue(result.verificationCheckId),
    evidence_item_id: nullableString(result.evidenceItemId),
    operation_id: nullableString(result.operationId),
    actor_principal_id: nullableString(result.actorPrincipalId),
    policy_basis: nullableString(result.policyBasis),
    target_graph_item_id: nullableString(result.targetGraphItemId),
    work_run_id: nullableString(result.workRunId),
    work_packet_version_id: nullableString(result.workPacketVersionId)
  };
}

function graphQLMissingEvidence(value: unknown): OperatorMissingEvidence {
  const evidence = record(value);

  return {
    verification_check_id: stringValue(evidence.verificationCheckId),
    reason: stringValue(evidence.reason)
  };
}

function graphQLPacketReadinessInput(input: PacketReadinessInput) {
  return {
    sourceGraphItemIds: input.source_graph_item_ids,
    verificationCheckIds: input.verification_check_ids
  };
}

function record(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {};
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function stringArray(value: unknown): string[] {
  return arrayValue(value).flatMap((item) => (typeof item === "string" ? [item] : []));
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : "";
}

function nullableString(value: unknown) {
  return typeof value === "string" ? value : null;
}

function booleanValue(value: unknown) {
  return typeof value === "boolean" ? value : false;
}

function numberValue(value: unknown) {
  return typeof value === "number" ? value : 0;
}

const itemFields = `
  type
  typedId { type id }
  normalizedEventId
  duplicateOfId
  status
  reasonCodes
  source { identity replayIdentity outcome }
  proposedChangeStatus { pending applied rejected total }
  blockerReasons
  allowedNextActions
  operationWatermark
  sourceWatermark
  graphLinks { type id graphItemId title state }
  graphRelationships { id sourceGraphItemId targetGraphItemId relationshipType }
  auditTrace { operationId resourceCount resources { type id } }
  revisionTrace { operationId resourceCount resources { type id } }
`;

const runStateFields = `
  type
  status
  allowedNextActions
  sourceWatermark
  packet { id title state }
  packetVersion { id versionNumber lifecycleState objective }
  run { id aggregateState executionState verificationState }
  requiredChecks { id verificationCheckId state }
  observations {
    id
    verificationCheckId
    graphItemId
    normalizedStatus
    freshnessState
    trustBasis
    sourceKind
    sourceIdentity
  }
  evidenceCandidates {
    id
    verificationCheckId
    executionObservationId
    claim
    state
    freshnessState
    trustBasis
    sourceKind
    sourceIdentity
  }
  evidenceItems { id state candidateId workRunId }
  verificationResults {
    id
    result
    verificationCheckId
    evidenceItemId
    operationId
    actorPrincipalId
    policyBasis
    targetGraphItemId
    workRunId
    workPacketVersionId
  }
  missingEvidence { verificationCheckId reason }
`;

const operatorInboxQuery = `
  query OperatorInbox {
    operatorInbox {
      type
      empty
      sourceWatermark
      rows { ${itemFields} }
    }
  }
`;

const operatorWorkflowItemQuery = `
  query OperatorWorkflowItem($id: ID!) {
    operatorWorkflowItem(id: $id) { ${itemFields} }
  }
`;

const operatorPacketReadinessQuery = `
  query OperatorPacketReadiness($input: OperatorPacketReadinessInput!) {
    operatorPacketReadiness(input: $input) {
      type
      ready
      status
      allowedNextActions
      blockerReasons
      sourceLinks { type id graphItemId title }
      requiredChecks { id graphItemId state }
      sourceWatermark
    }
  }
`;

const operatorRunStateQuery = `
  query OperatorRunState($id: ID!) {
    operatorRunState(id: $id) { ${runStateFields} }
  }
`;

const operatorVerificationOutcomeQuery = `
  query OperatorVerificationOutcome($id: ID!) {
    operatorVerificationOutcome(id: $id) {
      type
      status
      sourceWatermark
      run { id aggregateState executionState verificationState }
      verificationResults {
        id
        result
        verificationCheckId
        evidenceItemId
        operationId
        actorPrincipalId
        policyBasis
        targetGraphItemId
        workRunId
        workPacketVersionId
      }
      missingEvidence { verificationCheckId reason }
    }
  }
`;
