## ADDED Requirements

### Requirement: Manual API Compatibility Ledger

Office Graph SHALL maintain a compatibility ledger for hand-written GraphQL
and JSON API surfaces that remain during Ash API migration.

#### Scenario: Manual API surface remains live

- **WHEN** a manual Absinthe root field, Phoenix JSON route, serializer, or
  transport-specific resolver remains live after stabilization begins
- **THEN** the implementation MUST document the owning capability, reason it
  cannot yet be generated through AshGraphql or AshJsonApi, replacement target,
  parity tests, and retirement condition

#### Scenario: New manual API surface is proposed

- **WHEN** a change proposes new custom GraphQL or JSON API behavior
- **THEN** the design MUST classify it as a command exception, projection
  exception, integration/webhook exception, or temporary compatibility path and
  MUST prove why generated Ash API declarations are not the default path

### Requirement: Generated Ash Resource Reads Come First

Office Graph SHALL introduce generated AshGraphql and AshJsonApi resource
surfaces for safe reads before exposing generated lifecycle writes.

#### Scenario: Resource surface is migrated

- **WHEN** a WorkGraph, WorkPackets, Runs, or Verification resource read is
  migrated away from manual transport code
- **THEN** the migration MUST first expose authorized generated reads or simple
  read-model actions and MUST keep lifecycle-driving creates and updates
  private unless a spec explicitly makes them public

#### Scenario: Private action exists on resource

- **WHEN** an Ash resource action is marked private or is used only by an
  owning domain command
- **THEN** GraphQL and JSON API generation MUST NOT expose that action merely
  because the resource has AshGraphql or AshJsonApi extensions

### Requirement: Custom Commands Stay Thin

Office Graph SHALL keep custom API command and projection code thin when
generated Ash APIs do not fit.

#### Scenario: Command spans multiple bounded contexts

- **WHEN** a GraphQL mutation or JSON endpoint coordinates packets, runs,
  observations, evidence, verification, operations, authorization, or audit
- **THEN** the transport code MUST load context, call an owning public domain
  command, map transport-specific errors, and MUST NOT own lifecycle,
  authorization, idempotency, validation, or audit behavior

#### Scenario: Projection spans multiple resource types

- **WHEN** a GraphQL field or JSON endpoint returns a policy-filtered mixed
  projection
- **THEN** the transport code MUST call the owning projection contract and MUST
  NOT infer business semantics from raw resource type strings or private table
  structure

### Requirement: API Migration Maintains Parity

Office Graph SHALL preserve GraphQL and JSON API parity while migrating from
manual compatibility surfaces to generated Ash surfaces and custom command
exceptions.

#### Scenario: Replacement API is introduced

- **WHEN** a generated Ash API or new custom command/projection replaces a
  manual compatibility endpoint
- **THEN** tests MUST prove equivalent authorization behavior, operation
  context, validation errors, idempotency semantics, durable state changes, and
  safe structured error shapes for both GraphQL and JSON API where both
  transports are supported
