# execution-package-handoffs Specification

## Purpose
Define authority-preserving handoffs of execution packages and operation context between actors.
## Requirements
### Requirement: Handoffs Preserve Authority And Operation Context

Office Graph SHALL hand work packet versions to humans, agents, and future run
records through explicit authority and operation-context references.

#### Scenario: Packet is handed to a human

- **WHEN** a packet version is assigned or accepted for human execution
- **THEN** Office Graph MUST preserve assignee principal, assigner or
  delegator, authority basis, packet version, scope, readiness result,
  operation context, and required approvals or escalations

#### Scenario: Packet is handed to an agent

- **WHEN** a packet version is delegated to the internal agent runtime
- **THEN** Office Graph MUST preserve agent principal, delegator or trigger
  authority, packet version, autonomy envelope, context package reference,
  allowed capabilities, tool and credential limits, operation context, and
  unresolved approval or expansion requirements

### Requirement: Agent Handoffs Use Runtime Contracts

Office Graph SHALL use agent runtime entrypoint and context package contracts
when delegating packet work to an internal agent.

#### Scenario: Agent run request is prepared

- **WHEN** a packet is agent-ready and a delegated or automatic agent run is
  requested
- **THEN** the handoff MUST call the agent runtime contract with selected graph
  context, authorized context package, authority basis, autonomy envelope,
  approval state, and packet version reference

#### Scenario: Agent requests broader context

- **WHEN** an agent delegated from a packet needs broader scope, sensitivity,
  tool access, credential use, or external-write authority
- **THEN** the request MUST become a context expansion or approval flow linked
  to the packet version, agent activity, governing policy, and operation
  context

### Requirement: Execution Outputs Return Through Domain Contracts

Office Graph SHALL route execution outputs through change proposals,
evidence candidates, accepted domain actions, or future run/verification
contracts rather than hidden packet side effects.

#### Scenario: Execution proposes graph mutation

- **WHEN** a human or agent execution output proposes creating, updating,
  linking, closing, approving, rejecting, waiving, or attaching evidence to
  graph or domain state
- **THEN** Office Graph MUST route the output through change proposal or
  accepted domain action contracts with validation, authorization, revision,
  audit, and operation correlation

#### Scenario: Execution produces evidence

- **WHEN** a human, agent, integration, provider event, or future run produces
  proof or counterproof for packet success criteria
- **THEN** Office Graph MUST represent it as evidence candidate, evidence,
  check result, approval evidence, waiver, or future run event linked to the
  packet version and relevant checks

### Requirement: Escalation Paths Are Explicit

Office Graph SHALL model escalation and fallback paths for packets that cannot
continue safely.

#### Scenario: Execution cannot continue

- **WHEN** a human, agent, runtime, worker, or integration cannot continue
  because of missing context, failed authorization, approval timeout, tool
  failure, policy denial, stale packet, or ambiguous success criteria
- **THEN** the handoff MUST create or update a linked blocker, question,
  approval request, context expansion request, escalation item, or failure
  record instead of silently dropping work

#### Scenario: Escalation is resolved

- **WHEN** an escalation receives a decision, approval, denial, new packet
  version, context expansion result, or cancellation
- **THEN** the affected packet readiness and execution handoff state MUST be
  recomputable from the resolution and preserved links

### Requirement: Future Runs Reference Packet Versions

Office Graph SHALL ensure future run records can reference the exact packet
version that triggered or constrained execution.

#### Scenario: Run is created from packet

- **WHEN** `design-runs-and-verification` introduces run records for packet
  execution
- **THEN** each run created from a packet MUST reference the packet version,
  readiness result, authority basis, operation context, context package, and
  selected execution mode used at handoff

#### Scenario: Packet changes after run starts

- **WHEN** a packet is superseded, invalidated, or recompiled after a run
  starts
- **THEN** the existing run MUST continue to reference the original packet
  version while new execution is directed through the replacement or
  re-evaluated packet version
