## Implementation Summary

### Projection Contract

- `OfficeGraph.Projections.operator_inbox/1` returns the operator inbox with
  `empty?`, `source_watermark`, and workflow rows for manual intake triage.
- `OfficeGraph.Projections.operator_workflow_item/2` returns one intake row
  with proposed-change counts, allowed next actions, graph links,
  relationships, audit trace, and revision trace.
- `OfficeGraph.Projections.packet_readiness/2` returns packet-ready or blocked
  state with required checks, source links, and blocker reasons.
- `OfficeGraph.Projections.operator_run_state/2` returns packet, run,
  observation, candidate evidence, accepted evidence, verification result, and
  missing-evidence state.
- `OfficeGraph.Projections.verification_outcome/2` exposes the verification
  subset of the run projection.

### Status Vocabulary

- Inbox/item statuses: `pending_triage`, `ready_for_packet`,
  `not_actionable`.
- Packet readiness statuses: `packet_ready`, `blocked`.
- Run statuses: `awaiting_execution`, `awaiting_evidence`,
  `awaiting_evidence_acceptance`, `verified`, `failed`.
- Common blocker or reason codes include `duplicate_intake`,
  `no_proposed_changes`, `rejected_proposed_change`, `missing_objective`,
  `missing_success_criteria`, `missing_source_graph_items`,
  `missing_verification_checks`, `unsupported_autonomy_posture`,
  `missing_or_forbidden_source_graph_item`, and
  `missing_or_forbidden_verification_check`.

### Transport Surface

- Shared read functions live in `OfficeGraph.ApiSupport` and delegate to
  `OfficeGraph.Projections`.
- JSON routes live under `/api/operator-workflow/*` and serialize the same
  projection maps through `OfficeGraphWeb.OperatorWorkflowSerializer`.
- GraphQL query fields expose the same contracts through `operatorInbox`,
  `operatorWorkflowItem`, `operatorPacketReadiness`, `operatorRunState`, and
  `operatorVerificationOutcome`.
- JSON exposes snake_case keys; GraphQL exposes camelCase fields. Business
  state, allowed actions, blocker reasons, empty-state semantics, and source
  watermarks are shared.

### Requirement Mapping

- Manual intake entry and duplicate handling are covered by
  `OfficeGraph.Projections.OperatorWorkflowTest` and
  `OfficeGraphWeb.OperatorWorkflowApiTest`.
- Actionable inbox triage and applied graph links are covered by projection
  tests and GraphQL/JSON parity tests.
- Packet handoff readiness is covered by projection tests, API parity tests,
  and the existing packet-run verification command tests.
- Evidence and verification closure are covered by projection run-state tests,
  the JSON end-to-end operator workflow test, and existing packet/run/evidence
  command tests.
- Deferred surfaces remain out of scope; this change adds no provider polling,
  full agent runtime, broad React UI, graph canvas, ordered placement,
  collaborative rich text, mobile, or workflow-builder behavior.

### Verification Evidence

- `mix test test/office_graph/projections/operator_workflow_test.exs`
- `mix test test/office_graph_web/operator_workflow_api_test.exs`
- `mix test test/office_graph/projections/operator_workflow_test.exs test/office_graph_web/operator_workflow_api_test.exs test/office_graph_web/packet_run_verification_api_test.exs test/office_graph/work_packets/work_packet_run_verification_test.exs test/office_graph/work_graph/walking_skeleton_test.exs`
- `openspec validate design-first-operator-workflow --strict`
