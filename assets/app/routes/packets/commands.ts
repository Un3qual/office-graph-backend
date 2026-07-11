import { graphql } from "react-relay";

export const PacketsCreateWorkPacketMutation = graphql`
  mutation PacketsCreateWorkPacketMutation($input: CreateWorkPacketInput!) {
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

export const PacketsCreateWorkPacketVersionMutation = graphql`
  mutation PacketsCreateWorkPacketVersionMutation(
    $input: CreateWorkPacketVersionInput!
  ) {
    createWorkPacketVersion(input: $input) {
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

export const PacketsStartWorkRunMutation = graphql`
  mutation PacketsStartWorkRunMutation($input: StartWorkRunInput!) {
    startWorkRun(input: $input) {
      command
      operationId
      affectedIds {
        type
        id
      }
      run {
        id
        executionState
        verificationState
      }
      requiredChecks {
        id
        verificationCheckId
        state
      }
    }
  }
`;
