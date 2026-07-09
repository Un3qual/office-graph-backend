import { graphql } from "react-relay";
import {
  type RecordSourceSelectorProxy,
  type SelectorStoreUpdater
} from "relay-runtime";
import type { ExecutePacketRunVerificationMutation$data } from "../../relay/__generated__/ExecutePacketRunVerificationMutation.graphql";

export const OperatorWorkflowRouteQuery = graphql`
  query OperatorWorkflowRouteQuery($first: Int!, $after: String) {
    operatorWorkflowItems(first: $first, after: $after) {
      edges {
        cursor
        node {
          id
          ...OperatorWorkflowItemFragment
        }
      }
      pageInfo {
        hasNextPage
        hasPreviousPage
        startCursor
        endCursor
      }
    }
  }
`;

export const OperatorWorkflowItemFragment = graphql`
  fragment OperatorWorkflowItemFragment on OperatorWorkflowItem @inline {
    id
    type
    typedId {
      type
      id
    }
    normalizedEventId
    duplicateOfId
    status
    reasonCodes
    source {
      identity
      replayIdentity
      outcome
    }
    proposedChangeStatus {
      pending
      applied
      rejected
      total
    }
    blockerReasons
    allowedNextActions
    commandAffordances {
      identity
      state
      reasonCodes
      blockerReasons
      safeExplanation
      requiredFields
      inputDefaults {
        field
        value
        values
      }
    }
    operationWatermark
    sourceWatermark
    graphLinks {
      type
      id
      graphItemId
      title
      state
    }
    graphRelationships {
      id
      sourceGraphItemId
      targetGraphItemId
      relationshipType
    }
    auditTrace {
      operationId
      resourceCount
    }
    revisionTrace {
      operationId
      resourceCount
    }
  }
`;

export const OperatorPacketReadinessFragment = graphql`
  fragment OperatorPacketReadinessFragment on OperatorPacketReadiness @inline {
    type
    ready
    status
    allowedNextActions
    commandAffordances {
      identity
      state
      reasonCodes
      blockerReasons
      safeExplanation
      requiredFields
      inputDefaults {
        field
        value
        values
      }
    }
    blockerReasons
    sourceLinks {
      title
    }
    requiredChecks {
      state
    }
    sourceWatermark
  }
`;

export const OperatorPacketReadinessQuery = graphql`
  query OperatorPacketReadinessQuery($input: OperatorPacketReadinessInput!) {
    operatorPacketReadiness(input: $input) {
      ...OperatorPacketReadinessFragment
    }
  }
`;

export const OperatorRunStateFragment = graphql`
  fragment OperatorRunStateFragment on OperatorRunState @inline {
    type
    status
    allowedNextActions
    commandAffordances {
      identity
      state
      reasonCodes
      blockerReasons
      safeExplanation
      requiredFields
      inputDefaults {
        field
        value
        values
      }
    }
    sourceWatermark
    packet {
      id
      title
      state
    }
    packetVersion {
      id
      versionNumber
      lifecycleState
      objective
    }
    run {
      id
      aggregateState
      executionState
      verificationState
    }
    requiredChecks {
      verificationCheckId
      state
    }
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
    evidenceItems {
      id
      state
      candidateId
      workRunId
    }
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
    missingEvidence {
      verificationCheckId
      reason
    }
  }
`;

export const OperatorRunStateQuery = graphql`
  query OperatorRunStateQuery($id: ID!) {
    operatorRunState(id: $id) {
      ...OperatorRunStateFragment
    }
  }
`;

export const ExecutePacketRunVerificationMutation = graphql`
  mutation ExecutePacketRunVerificationMutation($input: ExecutePacketRunVerificationInput!) {
    executePacketRunVerification(input: $input) {
      packet {
        id
        title
        state
      }
      packetVersion {
        id
        versionNumber
        lifecycleState
        objective
      }
      run {
        id
        aggregateState
        executionState
        verificationState
      }
      requiredChecks {
        id
        verificationCheckId
        state
      }
      observations {
        id
        normalizedStatus
        sourceKind
        sourceIdentity
      }
      evidenceItems {
        id
        state
        candidateId
        workRunId
      }
      verificationResults {
        id
        result
        evidenceItemId
        operationId
        workRunId
        workPacketVersionId
        actorPrincipalId
        policyBasis
        targetGraphItemId
      }
      missingEvidence {
        verificationCheckId
        reason
      }
    }
  }
`;

export function operatorWorkflowRouteRootID(rootID = "client:root") {
  return rootID;
}

export const updateOperatorWorkflowAfterVerification: SelectorStoreUpdater<
  ExecutePacketRunVerificationMutation$data
> = (store) => {
  store.invalidateStore();
  invalidateOperatorWorkflowRoot(store);

  const payload = store.getRootField("executePacketRunVerification");
  const runID = payload?.getLinkedRecord("run")?.getValue("id");

  if (typeof runID === "string") {
    store.getRoot().getLinkedRecord("operatorRunState", { id: runID })?.invalidateRecord();
    store.get(runID)?.invalidateRecord();
  }
};

function invalidateOperatorWorkflowRoot(
  store: RecordSourceSelectorProxy<ExecutePacketRunVerificationMutation$data>
) {
  store.getRoot().invalidateRecord();
}
