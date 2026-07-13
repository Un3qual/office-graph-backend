import { graphql } from "react-relay";

export const PacketsRouteQuery = graphql`
  query PacketsRouteQuery(
    $first: Int!
    $after: String
    $createdOperationId: ID
    $loadCreatedPacket: Boolean!
  ) {
    operatorPacketCreateAffordance {
      identity
      state
    }
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
    createdPacket: listWorkPackets(
      first: 1
      filter: { operationId: { eq: $createdOperationId } }
    ) @include(if: $loadCreatedPacket) {
      edges {
        node {
          id
          ...PacketsRoutePacketFragment
        }
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
  query PacketsWorkspaceDetailQuery($id: ID!, $versionFirst: Int!, $versionAfter: String) {
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
      versionHistory(first: $versionFirst, after: $versionAfter) {
        edges {
          cursor
          node {
            id
            versionNumber
            lifecycleState
            title
          }
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
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
