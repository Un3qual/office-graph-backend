import type { ExecutePacketRunVerificationMutation$data } from "./__generated__/ExecutePacketRunVerificationMutation.graphql";

export function operatorVerificationMutationPayload(
  overrides: Partial<ExecutePacketRunVerificationMutation$data["executePacketRunVerification"]> = {}
): ExecutePacketRunVerificationMutation$data {
  return {
    executePacketRunVerification: {
      packet: {
        id: "packet_1",
        title: "Packet ready for verification",
        state: "ready"
      },
      packetVersion: {
        id: "packet_version_1",
        versionNumber: 1,
        lifecycleState: "current",
        objective: "Verify packet-run evidence."
      },
      run: {
        id: "run_1",
        aggregateState: "completed",
        executionState: "completed",
        verificationState: "verified"
      },
      requiredChecks: [
        {
          id: "required_check_1",
          verificationCheckId: "verification_check_1",
          state: "satisfied"
        }
      ],
      observations: [
        {
          id: "observation_1",
          normalizedStatus: "passed",
          sourceKind: "manual",
          sourceIdentity: "operator"
        }
      ],
      evidenceItems: [
        {
          id: "evidence_item_1",
          state: "accepted",
          candidateId: "candidate_1",
          workRunId: "run_1"
        }
      ],
      verificationResults: [
        {
          id: "verification_result_1",
          result: "passed",
          evidenceItemId: "evidence_item_1",
          operationId: "operation_1",
          workRunId: "run_1",
          workPacketVersionId: "packet_version_1",
          actorPrincipalId: "principal_1",
          policyBasis: "owner_acceptance",
          targetGraphItemId: "graph_item_1"
        }
      ],
      missingEvidence: [],
      ...overrides
    }
  };
}
