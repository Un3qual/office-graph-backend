## ADDED Requirements

### Requirement: Evidence Commands Are Step Specific
Office Graph SHALL expose evidence candidate creation and evidence acceptance as
separate authenticated GraphQL and JSON API commands.

#### Scenario: Operator creates an evidence candidate
- **WHEN** an authorized operator submits a run, required check, eligible
  observation, claim, source, freshness, trust, sensitivity, and idempotency key
- **THEN** the command MUST create or replay one candidate without satisfying
  the check

#### Scenario: Operator accepts evidence
- **WHEN** an authorized operator submits a candidate, title, body, passed or
  failed result, policy basis, and idempotency key
- **THEN** the command MUST preserve candidate/run/check consistency, audit,
  revision, result-slot, and run-verification rules and return the resulting
  evidence and verification state

### Requirement: Required Checks Can Be Governedly Waived
Office Graph SHALL allow a specifically authorized operator to waive a required
verification check with durable reason and policy provenance.

#### Scenario: Operator waives a required check
- **WHEN** a session with `verification.waive` submits a pending run-required
  check, nonblank reason, policy basis, expected run state, and idempotency key
- **THEN** Office Graph MUST record a waived verification result, actor,
  operation, reason, and policy basis; satisfy only that run-required check; and
  recompute run verification state

#### Scenario: Waiver is not allowed
- **WHEN** the check is already satisfied, is outside the run packet contract,
  the run state is stale, or the session lacks `verification.waive`
- **THEN** Office Graph MUST reject the waiver without changing check or run
  state and MUST preserve the required authorization decision
