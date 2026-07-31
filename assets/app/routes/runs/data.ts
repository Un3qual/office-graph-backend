import { graphql } from "react-relay";

export const RunsRouteQuery = graphql`
  query RunsRouteQuery($first: Int!, $after: String) @throwOnFieldError {
    listWorkRuns(
      first: $first
      after: $after
      sort: [{ field: INSERTED_AT, order: DESC }]
    ) {
      edges {
        node {
          id
          objective
          aggregateState
          executionState
          verificationState
          insertedAt
          workPacket {
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
  @throwOnFieldError
  @refetchable(queryName: "RunActivityPaginationQuery")
  @argumentDefinitions(
    id: { type: "ID!" }
    first: { type: "Int", defaultValue: 5 }
    after: { type: "String" }
  ) {
    operatorRunState(id: $id) {
      activity(first: $first, after: $after)
        @catch(to: RESULT)
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
      missingEvidence {
        verificationCheckId
        reason
      }
    }
    run: getWorkRun(id: $id) {
      id
      aggregateState
      executionState
      verificationState
      workPacket {
        id
        title
      }
      workPacketVersion {
        id
        versionNumber
        lifecycleState
        objective
      }
      requiredChecks(first: 20, sort: [{ field: POSITION, order: ASC }]) {
        edges {
          node {
            id
            verificationCheckId
            state
          }
        }
        pageInfo {
          hasNextPage
        }
      }
      evidenceCandidates(first: 20, sort: [{ field: INSERTED_AT, order: ASC }]) {
        edges {
          node {
            id
            claim
            candidateState
          }
        }
        pageInfo {
          hasNextPage
        }
      }
      evidenceItems(first: 20, sort: [{ field: INSERTED_AT, order: ASC }]) {
        edges {
          node {
            id
            state
          }
        }
        pageInfo {
          hasNextPage
        }
      }
      verificationResults(first: 20, sort: [{ field: INSERTED_AT, order: ASC }]) {
        edges {
          node {
            id
            result
            verificationCheckId
            policyBasis
          }
        }
        pageInfo {
          hasNextPage
        }
      }
    }
  }
`;
