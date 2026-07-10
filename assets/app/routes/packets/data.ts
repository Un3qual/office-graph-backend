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
