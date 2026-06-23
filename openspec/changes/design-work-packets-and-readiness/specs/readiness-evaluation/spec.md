## ADDED Requirements

### Requirement: Readiness Evaluation Is Explainable
Office Graph SHALL evaluate work packet readiness as an explainable result with
status, reasons, missing inputs, and affected graph links.

#### Scenario: Readiness is evaluated
- **WHEN** a packet version is evaluated for human execution, agent execution,
  investigation, senior review, or human-only handling
- **THEN** the result MUST include readiness status, reason codes, blocking
  graph items, missing inputs, required decisions, relevant approval state,
  stale-context markers, policy constraints, and recommended next actions

#### Scenario: Readiness changes
- **WHEN** a packet moves from blocked to ready, ready to stale, human-ready to
  agent-ready, or agent-ready to human-only
- **THEN** Office Graph MUST preserve enough status history or event context to
  explain what changed and why

### Requirement: Agent Readiness Requires Explicit Autonomy Safety
Office Graph SHALL require stricter conditions for agent-ready packets than
for human-ready packets.

#### Scenario: Packet is evaluated for agent execution
- **WHEN** a packet is evaluated for internal agent execution
- **THEN** it MUST have an explicit autonomy envelope, authorized context
  package, allowed scopes, requested capabilities, tool and credential limits,
  data-control posture, approval requirements, context-boundary rationale, and
  fallback or escalation behavior

#### Scenario: Packet is human-ready but not agent-ready
- **WHEN** a packet has enough context for a human but lacks safe autonomy,
  authority, tool, credential, approval, or data-control constraints for an
  agent
- **THEN** Office Graph MUST classify it as human-ready, senior-review-needed,
  investigation-only, or human-only instead of agent-ready

### Requirement: Blockers Are First-Class Readiness Inputs
Office Graph SHALL model missing information, unresolved questions, unsafe
ambiguity, and unresolved approvals as first-class readiness blockers.

#### Scenario: Open question blocks execution
- **WHEN** a packet depends on an unanswered question, missing decision,
  conflicting requirement, unresolved approval gate, missing artifact, or
  policy ambiguity
- **THEN** readiness evaluation MUST link the blocker to the affected packet
  and graph items and MUST identify the action needed to unblock execution

#### Scenario: Blocker is resolved
- **WHEN** a blocker is answered, waived, approved, rejected, superseded, or no
  longer relevant
- **THEN** readiness evaluation MUST be able to recompute the packet status and
  preserve the relationship between the blocker resolution and the new status

### Requirement: Stale Context Affects Readiness
Office Graph SHALL downgrade or block readiness when packet context may no
longer match the current authorized graph state.

#### Scenario: Packet source changes
- **WHEN** source graph items, decisions, checks, evidence, artifacts,
  approvals, permissions, sensitivity labels, external references, or autonomy
  policy change after packet compilation
- **THEN** readiness evaluation MUST mark the packet stale, require
  recompilation, or explain why the change does not affect the packet

#### Scenario: Stale packet is displayed
- **WHEN** a user, agent, API, or realtime projection sees a stale packet
- **THEN** the response MUST expose a safe stale marker, affected source
  references when policy permits, and the required recompile or review action

### Requirement: Approval Gates Affect Readiness
Office Graph SHALL include governed approval gate state in packet readiness
without duplicating approval semantics inside the packet.

#### Scenario: Approval is required
- **WHEN** a packet requires approval for context expansion, sensitive data,
  external writes, credential use, destructive actions, waiver, final
  verification, or high-risk proposed graph changes
- **THEN** readiness evaluation MUST keep the relevant execution mode blocked
  until the governing approval gate is satisfied, waived, rejected, expired, or
  explicitly marked not required by policy

#### Scenario: Approval eligibility changes
- **WHEN** approver eligibility, separation-of-duties state, scope
  relationship, sensitivity label, expiration, or reapproval rule changes
- **THEN** readiness evaluation MUST recompute affected packet readiness and
  preserve why any prior approval remains valid or no longer satisfies the
  packet requirement
