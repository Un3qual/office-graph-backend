# Work Packets And Readiness Tasks

## 1. Direction Lock

- [x] 1.1 Confirm this change defines work packet and readiness design only
  and does not start Ash, Ecto, Phoenix, GraphQL, JSON API, React, agent
  runtime, run-event, or verification-engine implementation.
- [x] 1.2 Confirm work packets are versioned execution contracts over graph
  context and not authorization containers or task notes.
- [x] 1.3 Confirm packet context preserves source graph and typed-record
  references while allowing compiled execution snapshots.
- [x] 1.4 Confirm readiness is explainable status with reasons, blockers,
  stale markers, approvals, autonomy posture, and next actions rather than a
  boolean.
- [x] 1.5 Confirm agent-ready is stricter than human-ready.

## 2. Capability Specs

- [x] 2.1 Add `work-packet-contracts` requirements for versioned packet
  contract shape, source context references, supersession, and completion
  criteria.
- [x] 2.2 Add `readiness-evaluation` requirements for explainable readiness,
  agent autonomy safety, first-class blockers, stale context, and approval gate
  effects.
- [x] 2.3 Add `execution-package-handoffs` requirements for human and agent
  handoffs, runtime contracts, execution outputs, escalation paths, and future
  run references.
- [x] 2.4 Add `work-packet-projections` requirements for packet projections,
  readiness explanations, realtime invalidation hints, and product surface
  state separation.

## 3. Design Decisions

- [x] 3.1 Decide packets compile context but do not own graph truth.
- [x] 3.2 Decide packet versions are immutable after execution handoff.
- [x] 3.3 Decide approval gates remain governed requirements consumed by
  packet readiness instead of packet-local flags.
- [x] 3.4 Decide packet handoffs create explicit references and operation
  context rather than hidden side effects.
- [x] 3.5 Decide packet projections own work packet product read shapes.
- [x] 3.6 Capture open questions for first product flow, readiness
  materialization, status vocabulary, MVP packet sections, and stale-context
  triggers.

## 4. Follow-On Planning Work

- [x] 4.1 Feed agent runtime invocation envelope, context package, authority,
  and autonomy envelope requirements into this change.
- [x] 4.2 Feed persistence requirements for work packets, execution packages,
  readiness checks, approval gates, and agent-executable block constraints
  into this change.
- [x] 4.3 Feed work graph work-container scope, addressable graph items,
  checks, evidence, and projection context from the durable graph specs and
  `openspec/changes/archive/2026-06-23-design-work-graph-core` into this
  change.
- [x] 4.4 Feed enterprise governance capability, grant, approval gate,
  separation-of-duties, and manager/team-lead verification requirements from
  the durable governance specs and
  `openspec/changes/archive/2026-06-23-design-enterprise-governance` into this
  change.
- [x] 4.5 Feed packet handoff, packet version, readiness result, evidence
  candidate, and future run-reference requirements into
  `design-runs-and-verification`.

## 5. Validation

- [x] 5.1 Run `openspec status --change design-work-packets-and-readiness`.
- [x] 5.2 Run `openspec validate design-work-packets-and-readiness --strict`.
- [x] 5.3 Run `openspec validate --changes --strict`.
