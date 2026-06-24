# work-packet-contracts Specification

## Purpose
TBD - created by archiving change design-work-packets-and-readiness. Update Purpose after archive.
## Requirements
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
  conversations, change proposals, or prior runs
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

### Requirement: Initial Packet Contract Is Persisted As A Stable Version

Office Graph SHALL persist the first executable work-packet slice as a stable
packet version rather than as mutable packet fields alone.

#### Scenario: Packet version is created

- **WHEN** an authorized actor creates a work packet for execution
- **THEN** Office Graph MUST create a packet record and a first packet version
  that records organization, workspace, objective, context summary,
  requirements, success criteria, autonomy posture, source graph item
  references, required verification checks, operation correlation, lifecycle
  state, and version number

#### Scenario: Packet version is used for execution

- **WHEN** a work run starts from a packet
- **THEN** the work run MUST reference the selected packet version and MUST NOT
  depend on later mutation of the packet's current editable fields to explain
  the execution contract

### Requirement: Initial Packet Creation Preserves Typed Source References

Office Graph SHALL preserve source graph and verification references through
typed records in the initial packet creation path.

#### Scenario: Packet includes source work

- **WHEN** packet creation receives source tasks, review findings, graph items,
  artifacts, decisions, or verification checks
- **THEN** Office Graph MUST store typed source-reference rows or typed
  foreign keys that identify each source record and the rationale for including
  it

#### Scenario: Packet references inaccessible context

- **WHEN** the creating actor lacks access to a referenced source record
- **THEN** Office Graph MUST reject the reference or store only a
  policy-approved restricted placeholder instead of copying unauthorized
  source data into the packet version

### Requirement: Initial Packet Lifecycle Is Explicit

Office Graph SHALL implement a minimal packet lifecycle for the first execution
slice.

#### Scenario: Packet is ready for run creation

- **WHEN** a packet version has objective, success criteria, source references,
  required check references, operation context, and an allowed autonomy posture
- **THEN** Office Graph MUST be able to mark that version ready for execution
  and allow a work run to start from it

#### Scenario: Packet is missing verification expectations

- **WHEN** a packet version lacks required checks, success criteria, or an
  allowed verification expectation for its execution mode
- **THEN** Office Graph MUST keep the packet draft or not-ready and MUST NOT
  allow verified completion to be inferred from run status alone
