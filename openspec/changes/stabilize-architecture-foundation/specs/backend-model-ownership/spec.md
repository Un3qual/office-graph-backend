## ADDED Requirements

### Requirement: Exception Ledger Is A Burn-Down Contract

Office Graph SHALL treat the direct database and architecture exception ledger
as a burn-down contract rather than accepted steady-state architecture.

#### Scenario: Existing exception is touched

- **WHEN** code covered by an architecture exception ledger entry is modified
- **THEN** the implementation MUST either narrow or retire the exception, or
  explicitly justify why the same exception scope remains necessary

#### Scenario: Exception is retired

- **WHEN** a direct database, raw SQL, broad `authorize?: false`, or manual
  transaction exception is retired
- **THEN** tests MUST prove the replacement preserves authorization,
  idempotency, concurrency, operation correlation, audit/revision behavior, and
  partial-commit safety that justified the original exception

### Requirement: New Direct Database Paths Require Coverage

Office Graph SHALL reject new direct database mutation or raw SQL paths unless
they are covered by an accepted exception.

#### Scenario: Direct database mutation is added

- **WHEN** production code adds `Repo.insert`, `Repo.update`, `Repo.delete`,
  `Repo.insert_all`, raw SQL mutation, or a new transaction that mutates durable
  Office Graph records
- **THEN** architecture conformance MUST fail unless the path is owned by a
  bounded context, listed in the exception ledger, scoped to an allowed
  operation type, and backed by tests

#### Scenario: Raw SQL read is added

- **WHEN** production code adds raw SQL for validation, locking, replay,
  analytics, or read-model work
- **THEN** the exception MUST document why Ash queries or public domain reads
  are insufficient and MUST define the allowed read scope and retirement
  condition

### Requirement: Broad Authorization Bypass Is Accounted For

Office Graph SHALL account for broad Ash authorization bypasses used inside
domain internals.

#### Scenario: `authorize?: false` is introduced

- **WHEN** production code adds or broadens `authorize?: false` or
  authorization-bypassing Ash reads/writes
- **THEN** the path MUST be inside an owning domain boundary, protected by an
  explicit public authorization check or private command invariant, and covered
  by architecture conformance or an exception ledger entry

#### Scenario: Internal command bypasses Ash policy

- **WHEN** an internal command bypasses Ash policy for a private action
- **THEN** the command MUST verify actor, scope, capability, operation context,
  and lifecycle invariants before the bypassed action runs

### Requirement: Model Ownership Gate Covers API Exposure

Office Graph SHALL include API exposure checks in model ownership verification.

#### Scenario: Ash resource is API-exposed

- **WHEN** an Ash resource is exposed through AshGraphql, AshJsonApi, or custom
  transport code
- **THEN** verification MUST confirm the resource has one canonical owning
  domain, public/private action posture is intentional, and API exposure does
  not bypass the owning domain lifecycle contract
