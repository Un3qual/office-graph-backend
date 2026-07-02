import type {
  OperatorEvidenceCandidate,
  OperatorEvidenceItem,
  OperatorInbox,
  OperatorMissingEvidence,
  OperatorObservation,
  OperatorRunState,
  OperatorVerificationResult,
  OperatorWorkflowItem,
  PacketReadiness,
  Trace,
  VerificationOutcome
} from "./workflowTypes";

export function graphQLInbox(value: unknown): OperatorInbox {
  const inbox = requiredRecord(value, "operator inbox");

  return {
    type: "operator_inbox",
    empty: booleanValue(inbox.empty),
    sourceWatermark: nullableString(inbox.sourceWatermark),
    rows: arrayValue(inbox.rows).map(graphQLItem)
  };
}

export function graphQLItem(value: unknown): OperatorWorkflowItem {
  const item = requiredRecord(value, "operator workflow item");
  const typedId = record(item.typedId);
  const source = record(item.source);
  const proposed = record(item.proposedChangeStatus);

  const normalizedEventId = stringValue(item.normalizedEventId);

  return {
    type: "operator_workflow_item",
    typedId: {
      type: stringValue(typedId.type),
      id: stringValue(typedId.id)
    },
    normalizedEventId,
    title: normalizedEventId,
    duplicateOfId: nullableString(item.duplicateOfId),
    status: stringValue(item.status),
    reasonCodes: stringArray(item.reasonCodes),
    source: {
      identity: stringValue(source.identity),
      replayIdentity: stringValue(source.replayIdentity),
      outcome: stringValue(source.outcome)
    },
    proposedChangeStatus: {
      pending: numberValue(proposed.pending),
      applied: numberValue(proposed.applied),
      rejected: numberValue(proposed.rejected),
      total: numberValue(proposed.total)
    },
    blockerReasons: stringArray(item.blockerReasons),
    allowedNextActions: stringArray(item.allowedNextActions),
    operationWatermark: nullableString(item.operationWatermark),
    sourceWatermark: nullableString(item.sourceWatermark),
    graphLinks: arrayValue(item.graphLinks).map((link) => {
      const row = record(link);

      return {
        type: stringValue(row.type),
        id: stringValue(row.id),
        graphItemId: nullableString(row.graphItemId),
        title: stringValue(row.title),
        state: nullableString(row.state)
      };
    }),
    graphRelationships: arrayValue(item.graphRelationships).map((relationship) => {
      const row = record(relationship);

      return {
        id: stringValue(row.id),
        sourceGraphItemId: stringValue(row.sourceGraphItemId),
        targetGraphItemId: stringValue(row.targetGraphItemId),
        relationshipType: stringValue(row.relationshipType)
      };
    }),
    auditTrace: graphQLTrace(item.auditTrace),
    revisionTrace: graphQLTrace(item.revisionTrace)
  };
}

export function graphQLPacketReadiness(value: unknown): PacketReadiness {
  const readiness = record(value);

  return {
    type: "packet_readiness",
    ready: booleanValue(readiness.ready),
    status: stringValue(readiness.status),
    allowedNextActions: stringArray(readiness.allowedNextActions),
    blockerReasons: stringArray(readiness.blockerReasons),
    sourceLinks: arrayValue(readiness.sourceLinks).map((link) => {
      const row = record(link);

      return {
        type: stringValue(row.type),
        id: stringValue(row.id),
        graphItemId: stringValue(row.graphItemId),
        title: stringValue(row.title)
      };
    }),
    requiredChecks: arrayValue(readiness.requiredChecks).map((check) => {
      const row = record(check);

      return {
        id: stringValue(row.id),
        graphItemId: stringValue(row.graphItemId),
        state: stringValue(row.state)
      };
    }),
    sourceWatermark: nullableString(readiness.sourceWatermark)
  };
}

export function graphQLRunState(value: unknown): OperatorRunState {
  const runState = requiredRecord(value, "operator run state");
  const packet = record(runState.packet);
  const packetVersion = record(runState.packetVersion);
  const run = record(runState.run);

  return {
    type: "operator_run_state",
    status: stringValue(runState.status),
    allowedNextActions: stringArray(runState.allowedNextActions),
    sourceWatermark: nullableString(runState.sourceWatermark),
    packet: {
      id: stringValue(packet.id),
      title: stringValue(packet.title),
      state: stringValue(packet.state)
    },
    packetVersion: {
      id: stringValue(packetVersion.id),
      versionNumber: numberValue(packetVersion.versionNumber),
      lifecycleState: stringValue(packetVersion.lifecycleState),
      objective: stringValue(packetVersion.objective)
    },
    run: {
      id: stringValue(run.id),
      aggregateState: stringValue(run.aggregateState),
      executionState: stringValue(run.executionState),
      verificationState: stringValue(run.verificationState)
    },
    requiredChecks: arrayValue(runState.requiredChecks).map(graphQLRequiredCheck),
    observations: arrayValue(runState.observations).map(graphQLObservation),
    evidenceCandidates: arrayValue(runState.evidenceCandidates).map(graphQLEvidenceCandidate),
    evidenceItems: arrayValue(runState.evidenceItems).map(graphQLEvidenceItem),
    verificationResults: arrayValue(runState.verificationResults).map(graphQLVerificationResult),
    missingEvidence: arrayValue(runState.missingEvidence).map(graphQLMissingEvidence)
  };
}

export function verificationOutcomeFromRunState(runState: OperatorRunState): VerificationOutcome {
  return {
    type: "verification_outcome",
    status: runState.status,
    sourceWatermark: runState.sourceWatermark,
    run: runState.run,
    verificationResults: runState.verificationResults,
    missingEvidence: runState.missingEvidence
  };
}

function graphQLTrace(value: unknown): Trace {
  const trace = record(value);

  return {
    operationId: nullableString(trace.operationId),
    resourceCount: numberValue(trace.resourceCount),
    resources: arrayValue(trace.resources).map((resource) => {
      const row = record(resource);

      return {
        type: stringValue(row.type),
        id: stringValue(row.id)
      };
    })
  };
}

function graphQLRequiredCheck(value: unknown) {
  const check = record(value);

  return {
    id: stringValue(check.id),
    verificationCheckId: stringValue(check.verificationCheckId),
    state: stringValue(check.state)
  };
}

function graphQLObservation(value: unknown): OperatorObservation {
  const observation = record(value);

  return {
    id: stringValue(observation.id),
    verificationCheckId: stringValue(observation.verificationCheckId),
    graphItemId: nullableString(observation.graphItemId),
    normalizedStatus: stringValue(observation.normalizedStatus),
    freshnessState: stringValue(observation.freshnessState),
    trustBasis: stringValue(observation.trustBasis),
    sourceKind: stringValue(observation.sourceKind),
    sourceIdentity: stringValue(observation.sourceIdentity)
  };
}

function graphQLEvidenceCandidate(value: unknown): OperatorEvidenceCandidate {
  const candidate = record(value);

  return {
    id: stringValue(candidate.id),
    verificationCheckId: stringValue(candidate.verificationCheckId),
    executionObservationId: nullableString(candidate.executionObservationId),
    claim: stringValue(candidate.claim),
    state: stringValue(candidate.state),
    freshnessState: stringValue(candidate.freshnessState),
    trustBasis: stringValue(candidate.trustBasis),
    sourceKind: stringValue(candidate.sourceKind),
    sourceIdentity: stringValue(candidate.sourceIdentity)
  };
}

function graphQLEvidenceItem(value: unknown): OperatorEvidenceItem {
  const item = record(value);

  return {
    id: stringValue(item.id),
    state: stringValue(item.state),
    candidateId: nullableString(item.candidateId),
    workRunId: nullableString(item.workRunId)
  };
}

function graphQLVerificationResult(value: unknown): OperatorVerificationResult {
  const result = record(value);

  return {
    id: stringValue(result.id),
    result: stringValue(result.result),
    verificationCheckId: stringValue(result.verificationCheckId),
    evidenceItemId: nullableString(result.evidenceItemId),
    operationId: nullableString(result.operationId),
    actorPrincipalId: nullableString(result.actorPrincipalId),
    policyBasis: nullableString(result.policyBasis),
    targetGraphItemId: nullableString(result.targetGraphItemId),
    workRunId: nullableString(result.workRunId),
    workPacketVersionId: nullableString(result.workPacketVersionId)
  };
}

function graphQLMissingEvidence(value: unknown): OperatorMissingEvidence {
  const evidence = record(value);

  return {
    verificationCheckId: stringValue(evidence.verificationCheckId),
    reason: stringValue(evidence.reason)
  };
}

function requiredRecord(value: unknown, projectionName: string): Record<string, unknown> {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    const row = value as Record<string, unknown>;

    if (Object.keys(row).length > 0) {
      return row;
    }
  }

  throw new Error(`The GraphQL ${projectionName} projection was empty.`);
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
