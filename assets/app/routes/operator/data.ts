import { graphql } from "react-relay";
import {
  ConnectionHandler,
  type RecordSourceSelectorProxy,
  type SelectorStoreUpdater
} from "relay-runtime";
import type { ExecutePacketRunVerificationMutation$data } from "../../relay/__generated__/ExecutePacketRunVerificationMutation.graphql";

export const operatorWorkflowConnectionKey = "OperatorWorkflowRoute_operatorWorkflowItems";

export const OperatorWorkflowRouteQuery = graphql`
  query OperatorWorkflowRouteQuery($first: Int!, $after: String) {
    operatorWorkflowItems(first: $first, after: $after)
      @connection(key: "OperatorWorkflowRoute_operatorWorkflowItems") {
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
  fragment OperatorWorkflowItemFragment on OperatorWorkflowItem {
    id
    type
    normalizedEventId
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
      resources {
        type
        id
      }
    }
    revisionTrace {
      operationId
      resourceCount
      resources {
        type
        id
      }
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

export function operatorWorkflowRouteConnectionID(rootID = "client:root") {
  return ConnectionHandler.getConnectionID(rootID, operatorWorkflowConnectionKey);
}

export const updateOperatorWorkflowAfterVerification: SelectorStoreUpdater<
  ExecutePacketRunVerificationMutation$data
> = (store) => {
  invalidateOperatorWorkflowConnection(store);

  const payload = store.getRootField("executePacketRunVerification");
  const runID = payload?.getLinkedRecord("run")?.getValue("id");

  if (typeof runID === "string") {
    store.get(runID)?.invalidateRecord();
  }
};

function invalidateOperatorWorkflowConnection(
  store: RecordSourceSelectorProxy<ExecutePacketRunVerificationMutation$data>
) {
  const connection = ConnectionHandler.getConnection(store.getRoot(), operatorWorkflowConnectionKey);
  connection?.invalidateRecord();
}
