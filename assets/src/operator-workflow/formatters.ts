import type {
  OperatorEvidenceCandidate,
  OperatorObservation,
  OperatorVerificationResult
} from "./api";
import { listSummary } from "./presentation";
import { formatWorkflowStatus } from "./status";

export function packetInputText(value: string | undefined) {
  return value && value.trim() !== "" ? value : "None";
}

export function packetInputStatus(value: string | undefined) {
  return value && value.trim() !== "" ? formatWorkflowStatus(value) : "None";
}

export function formatObservationDetails(observations: OperatorObservation[]) {
  return listSummary(
    observations.map((observation) =>
      [
        observation.id,
        formatWorkflowStatus(observation.normalized_status),
        formatWorkflowStatus(observation.freshness_state),
        formatWorkflowStatus(observation.trust_basis),
        observation.source_identity
      ].join(" / ")
    ),
    2
  );
}

export function formatEvidenceCandidateDetails(candidates: OperatorEvidenceCandidate[]) {
  return listSummary(
    candidates.map((candidate) => {
      const observationId = candidate.execution_observation_id ?? "no observation";

      return [
        candidate.id,
        formatWorkflowStatus(candidate.state),
        formatWorkflowStatus(candidate.freshness_state),
        formatWorkflowStatus(candidate.trust_basis),
        candidate.source_identity,
        candidate.claim,
        `Observation ${observationId}`
      ].join(" / ");
    }),
    2
  );
}

export function formatVerificationResultDetails(results: OperatorVerificationResult[]) {
  return listSummary(
    results.map((result) =>
      [
        result.id,
        formatWorkflowStatus(result.result),
        `Evidence ${result.evidence_item_id ?? "none"}`,
        `Policy ${formatWorkflowStatus(result.policy_basis ?? "none")}`,
        `Operation ${result.operation_id ?? "none"}`,
        `Actor ${result.actor_principal_id ?? "none"}`,
        `Target ${result.target_graph_item_id ?? "none"}`
      ].join(" / ")
    ),
    2
  );
}
