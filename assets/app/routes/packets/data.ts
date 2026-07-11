import { graphql } from "react-relay";

export const PacketsRouteQuery = graphql`
  query PacketsRouteQuery($first: Int!, $after: String) {
    listWorkPackets(first: $first, after: $after) {
      edges {
        cursor
        node {
          id
          ...PacketsRoutePacketFragment
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

export const PacketsRoutePacketFragment = graphql`
  fragment PacketsRoutePacketFragment on WorkPacket @inline {
    id
    title
    state
    currentVersionId
    operationId
    updatedAt
  }
`;

export const PacketsWorkspaceDetailQuery = graphql`
  query PacketsWorkspaceDetailQuery($id: ID!) {
    operatorPacketWorkspace(id: $id) {
      sourceWatermark
      ready
      status
      blockerReasons
      allowedNextActions
      packet {
        id
        title
        state
        currentVersionId
        operationId
      }
      currentVersion {
        id
        versionNumber
        lifecycleState
        title
        objective
        contextSummary
        requirements
        successCriteria
        autonomyPosture
        sourceGraphItemIds
        verificationCheckIds
        operationId
        insertedAt
      }
      versions {
        id
        versionNumber
        lifecycleState
        title
        objective
        contextSummary
        requirements
        successCriteria
        autonomyPosture
        sourceGraphItemIds
        verificationCheckIds
        operationId
        insertedAt
      }
      commandAffordances {
        identity
        state
        reasonCodes
        blockerReasons
        safeExplanation
        requiredFields
        inputDefaults { field value values }
        targetIds { type id }
        traceLinks { type id }
        decisionLinks { type id }
      }
    }
  }
`;
