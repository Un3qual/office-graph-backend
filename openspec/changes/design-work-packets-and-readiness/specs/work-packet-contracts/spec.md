## ADDED Requirements

### Requirement: Work Packets Are Versioned Execution Contracts
Office Graph SHALL represent delegated work as versioned work packets with a
stable execution contract for humans, agents, and future runs.

#### Scenario: Work packet version is created
- **WHEN** a user, agent, integration, or workflow prepares bounded work for
  execution
- **THEN** Office Graph MUST create a work packet version that records
  objective, source graph items, owning scope, compiled context references,
  requirements, decisions, constraints, artifacts, autonomy envelope, success
  criteria, verification references, approval gates, and escalation rules

#### Scenario: Work packet version is handed off
- **WHEN** a work packet version is accepted for human execution, agent
  execution, or future run creation
- **THEN** that version MUST remain a stable record of the execution contract
  and MUST NOT be silently changed by later graph, policy, context, or
  verification updates

### Requirement: Packet Context References Source Records
Work packet versions SHALL preserve source graph and typed-record references
rather than copying graph truth into packet-owned fields.

#### Scenario: Packet context is compiled
- **WHEN** Office Graph compiles packet context from graph projections,
  decisions, requirements, checks, evidence, artifacts, external references,
  conversations, proposed changes, or prior runs
- **THEN** the packet MUST preserve typed references, graph identity, projection
  inputs, context package metadata, and enough rationale to explain why each
  included item is in scope

#### Scenario: Restricted context is relevant
- **WHEN** relevant context is outside the actor's tenant, scope, sensitivity,
  credential, data-control, or autonomy boundary
- **THEN** the packet MUST omit, redact, summarize, show a restricted
  placeholder, or request context expansion according to policy instead of
  granting access through packet membership

### Requirement: Packet Supersession Is Traceable
Office Graph SHALL supersede, invalidate, or recompile packet versions when
source context changes materially.

#### Scenario: Source context changes
- **WHEN** linked questions, decisions, requirements, checks, evidence,
  artifacts, graph relationships, approval gates, autonomy policy, or scoped
  permissions change after a packet version is compiled
- **THEN** Office Graph MUST mark affected packet versions stale, invalidated,
  or superseded and preserve traceable links from the old version to the
  replacement or unresolved stale state

#### Scenario: Superseded packet has execution history
- **WHEN** a superseded packet version has been handed to a human, agent, or
  run
- **THEN** Office Graph MUST preserve the original version for audit,
  verification, and run traceability while directing new execution to the
  replacement version when policy allows

### Requirement: Packet Completion Criteria Are Explicit
Work packet versions SHALL include success criteria, verification references,
and escalation rules before being treated as execution-ready.

#### Scenario: Completion criteria are missing
- **WHEN** a packet lacks success criteria, required checks, acceptable
  evidence, waiver policy, monitoring conditions, or escalation rules needed
  for the selected execution mode
- **THEN** readiness evaluation MUST mark the packet not ready or
  investigation-only rather than allowing verified completion by status claim
  alone

#### Scenario: Completion criteria exist
- **WHEN** a packet defines success criteria, required checks, evidence
  expectations, approval gates, and escalation rules
- **THEN** future execution and verification surfaces MUST be able to link
  outputs, evidence candidates, waivers, approvals, and failures back to that
  packet version
