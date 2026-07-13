# work-packet-projections Specification

## Purpose
Define authorization-filtered work-packet projections for operators and executors.
## Requirements
### Requirement: Work Packet Projections Are Authorization Filtered

Office Graph SHALL expose work packet context through authorization-filtered
projection contracts rather than ad hoc joins or raw packet tables.

#### Scenario: Work packet view is requested

- **WHEN** a user, agent, service account, integration, API client, or system
  job requests a work packet projection
- **THEN** Office Graph MUST filter packet version, source graph items,
  included context, artifacts, conversations, external references, readiness
  reasons, approvals, execution status, and verification summary through
  tenant, scope, sensitivity, relationship, tombstone, and policy rules

#### Scenario: Projection includes restricted context

- **WHEN** packet context references an item the requester cannot fully view
- **THEN** the projection MUST hide it, show a restricted placeholder, provide
  a policy-approved redacted summary, or omit the branch according to the
  packet and graph projection contracts

### Requirement: Readiness Explanations Are Projected

Office Graph SHALL expose packet readiness explanations through product, API,
and realtime projection contracts.

#### Scenario: User reviews packet readiness

- **WHEN** a user opens a work packet context, blocker list, question queue,
  workstream board, or agent handoff surface
- **THEN** the projection MUST include safe readiness status, reason codes,
  blockers, missing inputs, stale markers, approval state, autonomy posture,
  and next actions appropriate to the user's authorization

#### Scenario: Agent receives packet projection

- **WHEN** an embedded, delegated, or automatic agent receives packet context
- **THEN** the projection MUST preserve context-boundary rationale, omitted or
  redacted context markers, allowed scopes, approved capabilities, and
  escalation options needed for safe execution

### Requirement: Packet Realtime Events Are Projection Hints

Office Graph SHALL treat work packet realtime payloads as projection updates
or invalidation hints, not as authoritative packet state.

#### Scenario: Packet source changes

- **WHEN** packet version, readiness, source graph context, approval state,
  execution handoff, blocker, stale marker, or verification summary changes
- **THEN** the owning domain or projection layer MUST publish a typed event or
  invalidation hint that lets clients refetch or reconcile the authorized work
  packet projection

#### Scenario: Client reconnects

- **WHEN** a client reconnects after missed packet updates, stale cache, or
  authorization changes
- **THEN** the client MUST recover by reading the authoritative authorized
  packet projection or resource API rather than relying on missed realtime
  payloads

### Requirement: Packet UI Separates Contract From Execution State

Office Graph SHALL let product surfaces distinguish packet contract, readiness,
handoff, execution status, and verification state.

#### Scenario: Packet is shown in UI

- **WHEN** a frontend displays a work packet view, board row, blocker view,
  question queue entry, agent run link, or verification surface
- **THEN** the projection MUST distinguish packet version contract, readiness
  result, open blockers, approval gates, execution handoff state, future run
  references, evidence status, verification state, and supersession state

#### Scenario: Packet state is mixed with run state

- **WHEN** a packet has one or more human, agent, integration, or future run
  executions
- **THEN** the projection MUST preserve packet version identity and execution
  references separately so users can tell what was requested, who or what acted
  on it, what changed, and what still needs verification

### Requirement: Initial Packet Run Summary Projection Is Authorized

Office Graph SHALL expose an initial authorized summary projection for packet
versions, work runs, observations, and verification state.

#### Scenario: Packet run summary is requested

- **WHEN** an authorized API client requests the first packet-run summary
- **THEN** Office Graph MUST return packet identity, selected packet version,
  objective, readiness or lifecycle state, work-run state, child observation
  summaries, required checks, accepted evidence summaries, verification
  result state, missing evidence reasons, and safe operation references

#### Scenario: Requester lacks access

- **WHEN** a requester lacks access to packet context, work-run child activity,
  evidence, observations, or source records
- **THEN** Office Graph MUST filter, redact, omit, or reject the restricted
  fields according to policy and MUST NOT reveal unauthorized source payloads

### Requirement: Initial Projection Separates Contract Execution And Evidence

Office Graph SHALL keep packet contract, execution activity, and verification
evidence distinct in the first API projection.

#### Scenario: Summary contains a completed observation

- **WHEN** a work run has a successful execution observation but no accepted
  evidence for a required check
- **THEN** the projection MUST show the observation as execution activity and
  MUST show verification as missing or unverified

#### Scenario: Summary contains accepted evidence

- **WHEN** a required check has accepted evidence and a passing verification
  result
- **THEN** the projection MUST link the packet version, work run, check,
  evidence, and result without presenting the evidence payload as run status
  alone
