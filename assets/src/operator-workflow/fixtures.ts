import type {
  OperatorInbox,
  OperatorRunState,
  PacketReadiness,
  VerificationOutcome
} from "./api";

export const sampleInbox: OperatorInbox = {
  type: "operator_inbox",
  empty: false,
  source_watermark: "op_123",
  rows: [
    {
      type: "operator_workflow_item",
      typed_id: { type: "normalized_intake_event", id: "evt_1" },
      normalized_event_id: "evt_1",
      duplicate_of_id: null,
      status: "pending_triage",
      reason_codes: [],
      source: {
        identity: "manual:operator-console",
        replay_identity: "paste:operator-console",
        outcome: "accepted"
      },
      proposed_change_status: {
        pending: 4,
        applied: 0,
        rejected: 0,
        total: 4
      },
      blocker_reasons: [],
      allowed_next_actions: ["apply_proposed_changes"],
      operation_watermark: "op_123",
      source_watermark: "op_123",
      graph_links: [],
      graph_relationships: [],
      audit_trace: { operation_id: null, resource_count: 0, resources: [] },
      revision_trace: { operation_id: null, resource_count: 0, resources: [] }
    }
  ]
};

export const samplePacketReadiness: PacketReadiness = {
  type: "packet_readiness",
  ready: true,
  status: "packet_ready",
  allowed_next_actions: ["create_work_packet"],
  blocker_reasons: [],
  source_links: [
    {
      type: "verification_check",
      id: "check_1",
      graph_item_id: "graph_1",
      title: "Run console verification"
    }
  ],
  required_checks: [{ id: "check_1", graph_item_id: "graph_1", state: "open" }],
  source_watermark: null
};

export const sampleRunState: OperatorRunState = {
  type: "operator_run_state",
  status: "awaiting_evidence_acceptance",
  allowed_next_actions: ["accept_evidence"],
  source_watermark: "run_1",
  packet: { id: "packet_1", title: "Operator console packet", state: "active" },
  packet_version: {
    id: "version_1",
    version_number: 1,
    lifecycle_state: "active",
    objective: "Verify the operator console renders workflow state."
  },
  run: {
    id: "run_1",
    aggregate_state: "running",
    execution_state: "completed",
    verification_state: "pending"
  },
  required_checks: [{ id: "required_1", verification_check_id: "check_1", state: "open" }],
  observations: [],
  evidence_candidates: [
    { id: "candidate_1", state: "proposed", verification_check_id: "check_1" }
  ],
  evidence_items: [],
  verification_results: [],
  missing_evidence: [{ verification_check_id: "check_1", reason: "missing_evidence" }]
};

export const sampleVerificationOutcome: VerificationOutcome = {
  type: "verification_outcome",
  status: "awaiting_evidence_acceptance",
  source_watermark: "run_1",
  run: sampleRunState.run,
  verification_results: [],
  missing_evidence: sampleRunState.missing_evidence
};
