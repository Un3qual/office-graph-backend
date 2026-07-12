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
