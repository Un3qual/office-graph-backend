export type GraphQLRequest = {
  query: string;
  variables: Record<string, unknown>;
  signal?: AbortSignal;
};

export type GraphQLResponse = {
  data?: Record<string, unknown>;
  errors?: Array<{ message?: string }>;
};

export type GraphQLFetcher = (request: GraphQLRequest) => Promise<GraphQLResponse>;

export type Trace = {
  operationId: string | null;
  resourceCount: number;
  resources: Array<{ type: string; id: string }>;
};

export type OperatorWorkflowItem = {
  type: "operator_workflow_item";
  typedId: { type: string; id: string };
  normalizedEventId: string;
  title: string;
  duplicateOfId: string | null;
  status: string;
  reasonCodes: string[];
  source: {
    identity: string;
    replayIdentity: string;
    outcome: string;
  };
  proposedChangeStatus: {
    pending: number;
    applied: number;
    rejected: number;
    total: number;
  };
  blockerReasons: string[];
  allowedNextActions: string[];
  operationWatermark: string | null;
  sourceWatermark: string | null;
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
    relationshipType: string;
  }>;
  auditTrace: Trace;
  revisionTrace: Trace;
};

export type OperatorInbox = {
  type: "operator_inbox";
  empty: boolean;
  sourceWatermark: string | null;
  rows: OperatorWorkflowItem[];
};

export type PacketReadinessInput = {
  sourceGraphItemIds: string[];
  verificationCheckIds: string[];
};

export type PacketReadiness = {
  type: "packet_readiness";
  ready: boolean;
  status: string;
  allowedNextActions: string[];
  blockerReasons: string[];
  sourceLinks: Array<{ type: string; id: string; graphItemId: string; title: string }>;
  requiredChecks: Array<{ id: string; graphItemId: string; state: string }>;
  sourceWatermark: string | null;
  isDerived?: boolean;
};

export type OperatorRunState = {
  type: "operator_run_state";
  status: string;
  allowedNextActions: string[];
  sourceWatermark: string | null;
  packet: { id: string; title: string; state: string };
  packetVersion: {
    id: string;
    versionNumber: number;
    lifecycleState: string;
    objective: string;
  };
  run: {
    id: string;
    aggregateState: string;
    executionState: string;
    verificationState: string;
  };
  requiredChecks: Array<{ id: string; verificationCheckId: string; state: string }>;
  observations: OperatorObservation[];
  evidenceCandidates: OperatorEvidenceCandidate[];
  evidenceItems: OperatorEvidenceItem[];
  verificationResults: OperatorVerificationResult[];
  missingEvidence: OperatorMissingEvidence[];
};

export type OperatorObservation = {
  id: string;
  verificationCheckId: string;
  graphItemId: string | null;
  normalizedStatus: string;
  freshnessState: string;
  trustBasis: string;
  sourceKind: string;
  sourceIdentity: string;
};

export type OperatorEvidenceCandidate = {
  id: string;
  verificationCheckId: string;
  executionObservationId: string | null;
  claim: string;
  state: string;
  freshnessState: string;
  trustBasis: string;
  sourceKind: string;
  sourceIdentity: string;
};

export type OperatorEvidenceItem = {
  id: string;
  state: string;
  candidateId: string | null;
  workRunId: string | null;
};

export type OperatorVerificationResult = {
  id: string;
  result: string;
  verificationCheckId: string;
  evidenceItemId: string | null;
  operationId: string | null;
  actorPrincipalId: string | null;
  policyBasis: string | null;
  targetGraphItemId: string | null;
  workRunId: string | null;
  workPacketVersionId: string | null;
};

export type OperatorMissingEvidence = {
  verificationCheckId: string;
  reason: string;
};

export type VerificationOutcome = {
  type: "verification_outcome";
  status: string;
  sourceWatermark: string | null;
  run: OperatorRunState["run"];
  verificationResults: OperatorRunState["verificationResults"];
  missingEvidence: OperatorRunState["missingEvidence"];
};
