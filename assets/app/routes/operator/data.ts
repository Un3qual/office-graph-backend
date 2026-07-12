import { graphql } from "react-relay";

export const OperatorWorkflowRouteQuery = graphql`
  query OperatorWorkflowRouteQuery($first: Int!, $after: String) {
    operatorManualIntakeAffordance {
      identity
      state
    }
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
      targetIds { type id }
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
      targetIds { type id }
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
      targetIds { type id }
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
      id
      graphItemId
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
