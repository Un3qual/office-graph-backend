import { graphql } from "react-relay";

export const RunsRouteQuery = graphql`
  query RunsRouteQuery($first: Int!, $after: String) @throwOnFieldError {
    operatorRuns(first: $first, after: $after) {
      edges {
        node {
          id
          objective
          aggregateState
          executionState
          verificationState
          insertedAt
          packet {
            title
          }
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
`;

export const RunActivityFragment = graphql`
  fragment RunActivityFragment on RootQueryType
  @refetchable(queryName: "RunActivityPaginationQuery")
  @argumentDefinitions(
    id: { type: "ID!" }
    first: { type: "Int", defaultValue: 5 }
    after: { type: "String" }
  ) {
    operatorRunState(id: $id) {
      activity(first: $first, after: $after)
        @connection(key: "RunActivityFragment_activity") {
        edges {
          node {
            kind
            stableId
            title
            status
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
`;

export const RunDetailQuery = graphql`
  query RunDetailQuery($id: ID!, $activityFirst: Int!) @throwOnFieldError {
    ...RunActivityFragment @arguments(id: $id, first: $activityFirst)
    operatorRunState(id: $id) {
      status
      packet {
        relayId
        title
      }
      packetVersion {
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
      evidenceCandidates {
        id
        claim
        state
      }
      evidenceItems {
        id
        state
      }
      verificationResults {
        id
        result
        verificationCheckId
        policyBasis
      }
      missingEvidence {
        verificationCheckId
        reason
      }
    }
  }
`;
