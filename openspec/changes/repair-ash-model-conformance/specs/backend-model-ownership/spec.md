## ADDED Requirements

### Requirement: Durable Model Ash Ownership
Every durable table implemented by Office Graph SHALL have a canonical Ash
resource in the bounded context that owns its lifecycle.
`openspec/changes/repair-ash-model-conformance/model-inventory.md` SHALL be
the normative 40-table inventory used by the architecture conformance gate.

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
  `openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md`
  with its owner, reason, allowed operation type, approving spec, and
  retirement condition

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
  model definitions, and coverage in the existing
  `openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md`
  direct Ecto exception ledger
