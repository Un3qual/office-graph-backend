# operator-workflow Specification

## Purpose
Define the first operator-facing workflow that turns manual intake, proposed
graph changes, packet readiness, packet-backed runs, evidence, and verification
into a coherent loop exposed through the current GraphQL product path.

## Requirements
### Requirement: Operator Workflow Starts From Manual Intake
Office Graph SHALL expose manual intake as the first operator workflow entry
point without bypassing the shared intake, idempotency, and proposed-change
contracts.

#### Scenario: Operator submits messy signal
- **WHEN** an authorized operator submits a pasted report, review note, bug
  description, CI excerpt, or other manual signal
- **THEN** Office Graph MUST create or reuse the normalized manual intake
  event, preserve raw archive and replay identity, produce proposed graph
  changes when applicable, and expose the resulting item in the operator
  workflow projection with next actions

#### Scenario: Operator submits duplicate signal
- **WHEN** manual intake receives a replayed or duplicate signal for the same
  workspace and idempotency basis
- **THEN** the operator workflow MUST expose the accepted prior intake result
  or replay conflict without creating duplicate signals, tasks, findings,
  checks, packets, runs, evidence, or verification results

### Requirement: Operator Inbox Presents Actionable Triage State
Office Graph SHALL provide an authorization-filtered operator inbox that turns
intake and proposed graph state into actionable triage rows.

#### Scenario: Intake row is pending triage
- **WHEN** a manual intake event has pending proposed graph changes
- **THEN** the inbox row MUST include typed intake identity, source summary,
  proposed-change status, validation or authorization blockers, allowed next
  actions, operation watermark, and policy-safe links to affected graph items

#### Scenario: Proposed changes are applied
- **WHEN** an authorized operator applies the proposed changes for an intake
  row
- **THEN** the workflow MUST show the created signal, task, review
  finding, verification check, graph relationships, audit or revision traces,
  and the next readiness or packet action without requiring the client to query
  raw tables directly

#### Scenario: Triage row is not actionable
- **WHEN** an intake row is invalid, unauthorized, duplicate, already applied,
  rejected, stale, or missing required context
- **THEN** the inbox projection MUST expose a safe status, reason code, and
  recommended next action rather than presenting an enabled apply or handoff
  command

### Requirement: Readiness Guides Packet Handoff
Office Graph SHALL guide operators from triaged graph work to a stable work
packet version before execution starts.

#### Scenario: Packet can be prepared
- **WHEN** a triaged task, review finding, and required verification check have
  enough context for human or operator-run execution
- **THEN** the workflow MUST be able to present packet-ready inputs including
  objective, source references, context summary, requirements, success
  criteria, autonomy posture, required checks, and remaining readiness reasons

#### Scenario: Packet is not ready
- **WHEN** required context, decisions, success criteria, verification checks,
  authorization, scope, or autonomy posture is missing or unsafe
- **THEN** the workflow MUST keep the packet not ready, identify the blocking
  reasons, and prevent work-run start until the packet contract is ready

#### Scenario: Work run starts from ready packet
- **WHEN** an authorized operator starts execution from a ready packet version
- **THEN** Office Graph MUST create or reuse a packet-backed work run, copy the
  packet required checks into run required checks, and expose the run as
  awaiting execution or evidence according to its child observations and
  verification state

### Requirement: Evidence And Verification Close The Operator Loop
Office Graph SHALL make evidence capture and verification explicit before an
operator workflow item is considered complete.

#### Scenario: Evidence is recorded for a run
- **WHEN** a human note, provider observation, test result, artifact, or manual
  execution outcome is recorded for a work run
- **THEN** the workflow MUST expose the typed observation, evidence candidate
  or evidence item, related check, freshness, trust basis, and missing evidence
  state without marking the run verified by execution status alone

#### Scenario: Evidence satisfies required check
- **WHEN** policy or an authorized operator accepts passing evidence for every
  required verification check in the selected packet version or run
- **THEN** Office Graph MUST record verification results, update the workflow
  projection to verified, and preserve links to the accepted evidence,
  operation correlation, actor or policy basis, and affected graph items

#### Scenario: Evidence does not satisfy required check
- **WHEN** evidence is missing, stale, failed, unauthorized, unrelated to the
  required check, or rejected by policy
- **THEN** the workflow MUST keep the item unverified or failed with explicit
  missing-evidence, stale-evidence, failed-check, authorization, or policy
  reason codes

### Requirement: Operator Workflow Uses The GraphQL Product Path

Office Graph SHALL expose current operator workflow projections and commands
through the GraphQL product path. Retired JSON API shapes MAY appear only as
historical compatibility references or explicitly named migration/deletion
targets.

#### Scenario: Workflow state is read

- **WHEN** the GraphQL product path reads the operator workflow inbox, item
  detail, packet readiness, run state, evidence state, or verification outcome
- **THEN** the path MUST use the same public backend read function,
  authorization filtering, typed identifiers, status vocabulary, blocker
  reasons, empty-state semantics, and source watermark

#### Scenario: Workflow command is executed

- **WHEN** the GraphQL product path submits manual intake, applies proposed
  changes, prepares or starts a packet-backed run, records observation or
  evidence, or verifies completion
- **THEN** the path MUST call the same owning backend commands and return
  equivalent validation, authorization, idempotency, conflict, stale, and
  lifecycle errors

#### Scenario: Old API shape has no current caller
- **WHEN** an old operator workflow API request/response shape has no current
  product, integration, or local development caller
- **THEN** the implementation MUST remove that API shape instead of keeping it
  for old callers

### Requirement: Deferred Surfaces Stay Out Of The First Operator Workflow
Office Graph SHALL keep the first operator workflow focused on the manual intake
to verification loop and defer broader platform behavior.

#### Scenario: Deferred behavior is requested
- **WHEN** implementation of the first operator workflow encounters provider
  webhooks or polling, full agent runtime execution, broad React UI polish,
  full graph canvas, generic ordered placement, collaborative rich text,
  mobile, or workflow-builder behavior
- **THEN** the behavior MUST be deferred to a later accepted OpenSpec change
  unless it is strictly required to make the manual operator workflow pass its
  verification gate
