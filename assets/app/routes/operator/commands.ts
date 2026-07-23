import { graphql } from "react-relay";

export const OperatorSubmitManualIntakeMutation = graphql`
  mutation OperatorSubmitManualIntakeMutation($input: SubmitManualIntakeInput!) {
    submitManualIntake(input: $input) {
      command
      operationId
      affectedIds {
        type
        id
      }
      normalizedEventId
      proposedChangeIds
    }
  }
`;

export const OperatorApplyProposedChangesMutation = graphql`
  mutation OperatorApplyProposedChangesMutation($input: ApplyProposedChangesInput!) {
    applyProposedChanges(input: $input) {
      command
      operationId
      affectedIds {
        type
        id
      }
      signal {
        id
      }
      task {
        id
      }
      reviewFinding {
        id
      }
      verificationCheck {
        id
        graphItemId
      }
    }
  }
`;

export const OperatorCreateWorkPacketMutation = graphql`
  mutation OperatorCreateWorkPacketMutation($input: CreateWorkPacketInput!) {
    createWorkPacket(input: $input) {
      command
      operationId
      affectedIds {
        type
        id
      }
      packet {
        id
        currentVersionId
        title
        state
      }
      packetVersion {
        id
        versionNumber
        lifecycleState
      }
    }
  }
`;

export const OperatorRecordExecutionObservationMutation = graphql`
  mutation OperatorRecordExecutionObservationMutation(
    $input: RecordExecutionObservationInput!
  ) {
    recordExecutionObservation(input: $input) {
      command
      operationId
      affectedIds {
        type
        id
      }
      observation {
        id
        normalizedStatus
      }
      run {
        id
        executionState
        verificationState
      }
    }
  }
`;

export const OperatorCreateEvidenceCandidateMutation = graphql`
  mutation OperatorCreateEvidenceCandidateMutation(
    $input: CreateEvidenceCandidateInput!
  ) {
    createEvidenceCandidate(input: $input) {
      command
      operationId
      affectedIds {
        type
        id
      }
      evidenceCandidate {
        id
        candidateState
      }
    }
  }
`;

export const OperatorAcceptEvidenceMutation = graphql`
  mutation OperatorAcceptEvidenceMutation($input: AcceptEvidenceInput!) {
    acceptEvidence(input: $input) {
      command
      operationId
      affectedIds {
        type
        id
      }
      evidenceCandidate {
        id
        candidateState
      }
      evidenceItem {
        id
        state
      }
      verificationResult {
        id
        result
      }
      run {
        id
        executionState
        verificationState
      }
    }
  }
`;

export const OperatorWaiveVerificationCheckMutation = graphql`
  mutation OperatorWaiveVerificationCheckMutation(
    $input: WaiveVerificationCheckInput!
  ) {
    waiveVerificationCheck(input: $input) {
      command
      operationId
      affectedIds {
        type
        id
      }
      verificationResult {
        id
        result
      }
      requiredCheck {
        id
        verificationCheckId
        state
      }
      run {
        id
        executionState
        verificationState
      }
    }
  }
`;

export const OperatorInvokeAgentMutation = graphql`
  mutation OperatorInvokeAgentMutation($input: InvokeAgentInput!) {
    invokeAgent(input: $input) {
      command
      operationId
      affectedIds { type id }
      execution { id state stateVersion currentStepKey }
      contextPackageId
    }
  }
`;

export const OperatorCancelAgentExecutionMutation = graphql`
  mutation OperatorCancelAgentExecutionMutation($input: CancelAgentExecutionInput!) {
    cancelAgentExecution(input: $input) {
      command
      operationId
      affectedIds { type id }
      execution { id state stateVersion currentStepKey }
    }
  }
`;

export const OperatorStartRunConversationMutation = graphql`
  mutation OperatorStartRunConversationMutation($input: StartRunConversationInput!) {
    startRunConversation(input: $input) {
      command
      operationId
      affectedIds { type id }
      conversation { id runId graphItemId state stateVersion }
    }
  }
`;

export const OperatorAppendConversationMessageMutation = graphql`
  mutation OperatorAppendConversationMessageMutation($input: AppendConversationMessageInput!) {
    appendConversationMessage(input: $input) {
      command
      operationId
      affectedIds { type id }
      message { id }
    }
  }
`;

export const OperatorResolveAgentApprovalMutation = graphql`
  mutation OperatorResolveAgentApprovalMutation($input: ResolveAgentApprovalInput!) {
    resolveAgentApproval(input: $input) {
      command
      operationId
      affectedIds { type id }
      request { id state version }
      execution { id state stateVersion currentStepKey }
    }
  }
`;

export const OperatorResolveAgentContextExpansionMutation = graphql`
  mutation OperatorResolveAgentContextExpansionMutation(
    $input: ResolveAgentContextExpansionInput!
  ) {
    resolveAgentContextExpansion(input: $input) {
      command
      operationId
      affectedIds { type id }
      request { id state version }
      execution { id state stateVersion currentStepKey }
      contextPackageId
    }
  }
`;
