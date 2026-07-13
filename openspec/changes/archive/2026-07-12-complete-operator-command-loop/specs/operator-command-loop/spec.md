## ADDED Requirements

### Requirement: Operator Commands Advance One Durable Step
Office Graph SHALL expose the proving workflow as separate commands whose
results identify the affected durable record and allowed next actions.

#### Scenario: Operator advances the workflow
- **WHEN** an authorized operator submits intake, applies its proposal, creates
  or versions a packet, starts a run, records an observation, creates or accepts
  evidence, or waives a check
- **THEN** Office Graph MUST execute only that named step, return its affected
  record identities and operation identity, and MUST NOT silently execute later
  workflow steps

#### Scenario: Command succeeds
- **WHEN** a step-specific command commits
- **THEN** its result MUST contain enough typed identity and current state for
  Relay to refresh the affected inbox, packet, run, and verification records

### Requirement: Operator Commands Are Idempotent And Conflict Aware
Office Graph SHALL make retries safe without allowing changed input to reuse a
completed operation.

#### Scenario: Same command is retried
- **WHEN** the same actor retries the same command with the same idempotency key
  and equivalent input
- **THEN** Office Graph MUST return the original durable result without creating
  duplicate records or events

#### Scenario: Retry changes input
- **WHEN** a command reuses an idempotency key with different normalized input
- **THEN** Office Graph MUST return a stable conflict and MUST NOT mutate the
  original result

#### Scenario: Target state is stale
- **WHEN** a command names an expected version or lifecycle state that no longer
  matches the durable target
- **THEN** Office Graph MUST reject the command as stale and require the client
  to read authoritative state before retrying

### Requirement: Command Failures Are Safe And Actionable
Office Graph SHALL return stable command errors without leaking hidden policy,
transport, or internal exception details.

#### Scenario: Command input is invalid
- **WHEN** a command omits or supplies an invalid field
- **THEN** the API MUST return the command identity and field-specific safe
  validation details without creating partial durable writes

#### Scenario: Command is not authorized
- **WHEN** the session lacks the required capability or target visibility
- **THEN** the API MUST return a safe forbidden result and preserve the required
  authorization decision without revealing hidden target data
