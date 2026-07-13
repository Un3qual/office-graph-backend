## ADDED Requirements

### Requirement: Product Write APIs Use Step-Specific Commands
Office Graph SHALL expose product writes as thin GraphQL and JSON transport
modules over named domain commands and operation correlation.

#### Scenario: Product command is exposed
- **WHEN** a transport exposes manual intake, proposal apply, packet create or
  version, run start, observation, evidence, or waiver behavior
- **THEN** the transport MUST resolve the request session, parse transport
  input, start the named operation, call one owning domain command, and map its
  result or safe error without reimplementing domain workflow logic

#### Scenario: API families expose the command loop
- **WHEN** GraphQL and JSON API clients execute equivalent operator commands
- **THEN** both API families MUST enforce the same authorization, validation,
  idempotency, conflict, audit, and result semantics even when their transport
  envelopes differ

### Requirement: Unreleased One-Shot Workflow Mutation Is Removed
Office Graph SHALL remove the packet-run-verification one-shot transport after
step-specific commands replace its supported behavior.

#### Scenario: Replacement command sequence is verified
- **WHEN** API and product tests cover packet creation, run start, observation,
  evidence creation, and evidence acceptance as separate operations
- **THEN** the GraphQL schema MUST no longer expose
  `executePacketRunVerification`, and transport-only input and result modules
  with no current caller MUST be deleted
