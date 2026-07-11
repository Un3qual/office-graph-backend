## ADDED Requirements

### Requirement: Operator Console Executes Allowed Workflow Commands
The operator console SHALL render and execute enabled command affordances for
manual intake, proposal application, packet preparation, run progress,
evidence, and verification.

#### Scenario: Operator submits or advances work
- **WHEN** the current projection exposes an enabled command affordance
- **THEN** the console MUST render its route-owned form or action, submit the
  matching Relay mutation, disable duplicate submission while pending, and
  refresh the affected authoritative reads after success

#### Scenario: Command is disabled or hidden
- **WHEN** an affordance is disabled, hidden, or redacted
- **THEN** the console MUST NOT synthesize an enabled action and MUST preserve
  safe blocker or policy copy without revealing hidden targets

### Requirement: Operator Command Feedback Preserves Context
The operator console SHALL keep still-valid workflow context visible while a
command is pending or fails.

#### Scenario: Command validation fails
- **WHEN** a Relay mutation returns field errors
- **THEN** the owning form MUST show safe field feedback while preserving the
  inbox, selection, packet, and run context

#### Scenario: Command conflicts with durable state
- **WHEN** a command returns an idempotency or stale-state conflict
- **THEN** the console MUST show a safe conflict message, refresh the affected
  authoritative query, and require an explicit retry
