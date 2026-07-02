import type { GraphQLFetcher } from "./workflowTypes";

export function createGraphQLHttpFetcher({
  fetcher = fetch,
  path = "/graphql"
}: {
  fetcher?: typeof fetch;
  path?: string;
} = {}): GraphQLFetcher {
  return async ({ query, variables, signal }) => {
    const response = await fetcher(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal,
      body: JSON.stringify({ query, variables })
    });

    if (!response.ok) {
      throw new Error(`The GraphQL operator request failed with HTTP ${response.status}.`);
    }

    return response.json();
  };
}

const itemFields = `
  type
  typedId { type id }
  normalizedEventId
  duplicateOfId
  status
  reasonCodes
  source { identity replayIdentity outcome }
  proposedChangeStatus { pending applied rejected total }
  blockerReasons
  allowedNextActions
  operationWatermark
  sourceWatermark
  graphLinks { type id graphItemId title state }
  graphRelationships { id sourceGraphItemId targetGraphItemId relationshipType }
  auditTrace { operationId resourceCount resources { type id } }
  revisionTrace { operationId resourceCount resources { type id } }
`;

export const operatorInboxQuery = `
  query OperatorInbox($limit: Int, $offset: Int) {
    operatorInbox(limit: $limit, offset: $offset) {
      type
      empty
      hasMore
      limit
      nextOffset
      offset
      sourceWatermark
      rows { ${itemFields} }
    }
  }
`;

export const operatorItemQuery = `
  query OperatorWorkflowItem($id: ID!) {
    operatorWorkflowItem(id: $id) { ${itemFields} }
  }
`;

export const operatorPacketReadinessQuery = `
  query OperatorPacketReadiness($input: OperatorPacketReadinessInput!) {
    operatorPacketReadiness(input: $input) {
      type
      ready
      status
      allowedNextActions
      blockerReasons
      sourceLinks { type id graphItemId title }
      requiredChecks { id graphItemId state }
      sourceWatermark
    }
  }
`;

export const operatorRunStateQuery = `
  query OperatorRunState($id: ID!) {
    operatorRunState(id: $id) {
      type
      status
      allowedNextActions
      sourceWatermark
      packet { id title state }
      packetVersion { id versionNumber lifecycleState objective }
      run { id aggregateState executionState verificationState }
      requiredChecks { id verificationCheckId state }
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
      evidenceItems { id state candidateId workRunId }
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
      missingEvidence { verificationCheckId reason }
    }
  }
`;
