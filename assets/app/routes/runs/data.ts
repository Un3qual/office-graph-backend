import { graphql } from "react-relay";

export const RunsRouteQuery = graphql`
  query RunsRouteQuery($first: Int!, $after: String) @throwOnFieldError {
    operatorRuns(first: $first, after: $after) {
      edges {
        cursor
        node {
          id
          objective
          aggregateState
          executionState
          verificationState
          insertedAt
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

export const RunDetailQuery = graphql`
  query RunDetailQuery($id: ID!, $activityFirst: Int!, $activityAfter: String) @throwOnFieldError {
    operatorRunState(id: $id) {
      type
      status
      sourceWatermark
      packet {
        id
        relayId
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
      activity(first: $activityFirst, after: $activityAfter) {
        edges {
          cursor
          node {
            kind
            stableId
            title
            status
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
  }
`;
