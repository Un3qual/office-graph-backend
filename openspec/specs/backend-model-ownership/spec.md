# backend-model-ownership Specification

## Purpose

Define the durable model ownership contract for Office Graph tables, Ash
domains/resources, direct Ecto exception control, and the architecture
conformance gate that keeps implementation and accepted OpenSpec evidence in
sync.
## Requirements
### Requirement: Durable Model Ash Ownership

Every durable table implemented by Office Graph SHALL have a canonical Ash
resource in the bounded context that owns its lifecycle.
`openspec/specs/backend-model-ownership/model-inventory.md` SHALL be the
normative inventory used by the architecture conformance gate, and SHALL
distinguish implemented migration-created tables from accepted planned MVP
resources that have not been migrated yet.

#### Scenario: A migration-created table is implemented

- **WHEN** a table exists in a committed migration for the backend
- **THEN** the table MUST be represented by exactly one canonical Ash resource
  module registered in exactly one owning Ash domain

#### Scenario: A table-backed model module exists

- **WHEN** production code under `lib/office_graph` defines a durable model
- **THEN** it MUST use `Ash.Resource` with `AshPostgres.DataLayer` rather than
  `Ecto.Schema`

#### Scenario: An existing model is promoted

- **WHEN** an existing manual Ecto schema is promoted to Ash
- **THEN** the existing canonical module path MUST become the Ash resource
  unless an OpenSpec design explicitly approves a different public module path

#### Scenario: A planned MVP resource is accepted before migration

- **WHEN** an accepted or active OpenSpec design requires a typed MVP resource
  that is not present in committed migrations yet
- **THEN** the model inventory MUST list the planned table, owning domain,
  canonical Ash resource, source spec, and implementation status without
  counting it as part of the implemented migration-created table inventory

### Requirement: No Duplicate Model Definitions

Office Graph SHALL avoid parallel model definitions for the same durable table.

#### Scenario: A table has an Ash resource

- **WHEN** a table is represented by an Ash resource
- **THEN** production code MUST NOT also define a manual Ecto schema for that
  table

#### Scenario: WorkGraph resources are converged

- **WHEN** WorkGraph resources are Ash-backed
- **THEN** they MUST be defined as `OfficeGraph.WorkGraph.GraphItem`,
  `OfficeGraph.WorkGraph.GraphRelationship`, `OfficeGraph.WorkGraph.Signal`,
  `OfficeGraph.WorkGraph.Task`, `OfficeGraph.WorkGraph.ReviewFinding`,
  `OfficeGraph.WorkGraph.VerificationCheck`, `OfficeGraph.WorkGraph.Artifact`,
  `OfficeGraph.WorkGraph.EvidenceItem`, and
  `OfficeGraph.WorkGraph.VerificationResult` rather than parallel
  `OfficeGraph.WorkGraph.Resources.*` modules

### Requirement: Direct Ecto Exception Control

Office Graph SHALL keep direct Ecto outside normal model ownership and normal
domain mutations.

#### Scenario: Direct Ecto remains useful

- **WHEN** a context uses direct Ecto for a transaction boundary, read model,
  replay scan, bulk maintenance path, or raw SQL escape hatch
- **THEN** that path MUST be listed in
  `openspec/specs/backend-model-ownership/architecture-exceptions.md`
  with its owner, reason, allowed operation type, approving spec, and retirement
  condition

#### Scenario: A normal mutation is implemented

- **WHEN** production code creates, updates, or deletes a durable domain record
- **THEN** it MUST call the owning context command or Ash action rather than
  `Repo.insert`, `Repo.update`, `Repo.delete`, or schema changesets

### Requirement: Architecture Gate Covers Model Ownership

The backend verification gate SHALL fail when implementation and model
ownership specs diverge.

#### Scenario: Backend verification runs

- **WHEN** `mix architecture.conformance` or `./bin/verify-backend` runs
- **THEN** it MUST verify table inventory, Ash domain registration, Ash resource
  registration, absence of table-backed Ecto schemas, absence of duplicate
  model definitions, planned MVP graph/software-proving/rich-text resource
  coverage, and coverage in the existing
  `openspec/specs/backend-model-ownership/architecture-exceptions.md` direct
  Ecto exception ledger

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
