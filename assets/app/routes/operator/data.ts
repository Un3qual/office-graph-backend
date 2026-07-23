import { graphql } from "react-relay";

export const OperatorWorkflowRouteQuery = graphql`
  query OperatorWorkflowRouteQuery($first: Int!, $after: String) @throwOnFieldError {
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
    title
    sourceSummary
    proposedActionPreviews {
      action
      title
      status
    }
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
      definitionKey
    }
    relationshipSummary {
      graphLinks
      graphRelationships
      hasMore
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

export const OperatorRelationshipDetailsQuery = graphql`
  query OperatorRelationshipDetailsQuery($id: ID!, $first: Int!, $after: String)
  @throwOnFieldError {
    operatorRelationshipDetails(id: $id, first: $first, after: $after) {
      edges {
        cursor
        node { kind stableId title status linkType definitionKey }
      }
      pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
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
  query OperatorPacketReadinessQuery($input: OperatorPacketReadinessInput!) @throwOnFieldError {
    operatorPacketReadiness(input: $input) {
      ...OperatorPacketReadinessFragment
    }
  }
`;

export const OperatorRunStateFragment = graphql`
  fragment OperatorRunStateFragment on OperatorRunState
  @inline
  @argumentDefinitions(
    activityFirst: { type: "Int!", defaultValue: 5 }
    activityAfter: { type: "String" }
  ) {
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
    commandOptions {
      observation {
        key
        label
        runId
        verificationCheckId
        sourceGraphItemId
        observationSourceKind
        observationSourceIdentity
        freshnessState
        trustBasis
        defaultOutcomeKey
        outcomes {
          key
          label
          observedStatus
          normalizedStatus
        }
      }
      evidenceCandidate {
        key
        label
        workRunId
        verificationCheckId
        executionObservationId
        sourceKind
        sourceIdentity
        freshnessState
        trustBasis
        sensitivity
      }
      evidenceAcceptance {
        key
        label
        evidenceCandidateId
        result
        acceptancePolicyBasis
      }
      waiver {
        key
        label
        runId
        runRequiredCheckId
        expectedExecutionState
        expectedVerificationState
        policyBasis
      }
    }
    commandOptionsOverflow
    commandOptionSummary {
      observation
      evidenceCandidate
      evidenceAcceptance
      waiver
    }
    childSummary {
      requiredChecks
      observations
      evidenceCandidates
      evidenceItems
      verificationResults
      missingEvidence
      hasMore
    }
    activity(first: $activityFirst, after: $activityAfter) {
      edges {
        cursor
        node { kind stableId title status }
      }
      pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
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

export const OperatorRunCommandOptionPageQuery = graphql`
  query OperatorRunCommandOptionPageQuery(
    $id: ID!
    $first: Int!
    $observationAfter: String
    $evidenceCandidateAfter: String
    $evidenceAcceptanceAfter: String
    $waiverAfter: String
    $loadObservation: Boolean!
    $loadEvidenceCandidate: Boolean!
    $loadEvidenceAcceptance: Boolean!
    $loadWaiver: Boolean!
  ) @throwOnFieldError {
    observation: operatorRunCommandOptionPage(
      id: $id, kind: "observation", first: $first, after: $observationAfter
    ) @include(if: $loadObservation) {
      ...OperatorRunCommandOptionPageConnectionFragment
    }
    evidenceCandidate: operatorRunCommandOptionPage(
      id: $id, kind: "evidence_candidate", first: $first, after: $evidenceCandidateAfter
    ) @include(if: $loadEvidenceCandidate) {
      ...OperatorRunCommandOptionPageConnectionFragment
    }
    evidenceAcceptance: operatorRunCommandOptionPage(
      id: $id, kind: "evidence_acceptance", first: $first, after: $evidenceAcceptanceAfter
    ) @include(if: $loadEvidenceAcceptance) {
      ...OperatorRunCommandOptionPageConnectionFragment
    }
    waiver: operatorRunCommandOptionPage(
      id: $id, kind: "waiver", first: $first, after: $waiverAfter
    ) @include(if: $loadWaiver) {
      ...OperatorRunCommandOptionPageConnectionFragment
    }
  }
`;

export const OperatorRunCommandOptionPageConnectionFragment = graphql`
  fragment OperatorRunCommandOptionPageConnectionFragment on OperatorRunCommandOptionChoiceConnection @inline {
        edges {
          cursor
          node {
            observation {
              key label runId verificationCheckId sourceGraphItemId
              observationSourceKind observationSourceIdentity freshnessState trustBasis
              defaultOutcomeKey
              outcomes { key label observedStatus normalizedStatus }
            }
            evidenceCandidate {
              key label workRunId verificationCheckId executionObservationId
              sourceKind sourceIdentity freshnessState trustBasis sensitivity
            }
            evidenceAcceptance {
              key label evidenceCandidateId result acceptancePolicyBasis
            }
            waiver {
              key label runId runRequiredCheckId expectedExecutionState
              expectedVerificationState policyBasis
            }
          }
        }
        pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
  }
`;

export const OperatorRunStateQuery = graphql`
  query OperatorRunStateQuery($id: ID!, $activityFirst: Int!, $activityAfter: String)
  @throwOnFieldError {
    operatorRunState(id: $id) {
      ...OperatorRunStateFragment
        @arguments(activityFirst: $activityFirst, activityAfter: $activityAfter)
    }
  }
`;

export const OperatorRunConversationQuery = graphql`
  query OperatorRunConversationQuery($runId: ID!, $graphItemId: ID!) @throwOnFieldError {
    operatorRunConversation(runId: $runId, graphItemId: $graphItemId) {
      type
      sourceWatermark
      allowedNextActions
      commandAffordances {
        identity
        state
        reasonCodes
        blockerReasons
        safeExplanation
        requiredFields
        inputDefaults { field value values }
        targetIds { type id }
      }
      conversation {
        id
        runId
        graphItemId
        state
        stateVersion
      }
      messages {
        id
        source
        body
        executionId
        insertedAt
        referencedContext {
          visibility
          packageId
          version
          entries { posture rationaleCode }
        }
      }
      executions {
        id
        bindingId
        state
        stateVersion
        currentStepKey
        attemptCount
        failureCode
        requestedOutcome
        invocationMode
        origin
        autonomyMode
        insertedAt
        updatedAt
      }
      approvalRequests {
        id
        executionId
        stepKey
        requestedAction
        reason
        scopeType
        scopeId
        capabilityKey
        sensitivity
        externalWrite
        state
        version
        expiresAt
        resolutionReason
      }
      contextExpansionRequests {
        id
        executionId
        stepKey
        targetResourceType
        targetResourceId
        targetScopeType
        targetScopeId
        accessMode
        capabilityKey
        reason
        sensitivity
        expectedDurationSeconds
        state
        version
        expiresAt
        resolutionReason
      }
    }
  }
`;
