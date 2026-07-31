# migration-baseline Specification

## Purpose

Define the clean unreleased PostgreSQL schema baseline, Ash-owned canonical
setup, and empty-database verification contract.

## Requirements

### Requirement: Unreleased migration history has one current baseline

Office Graph SHALL represent its current PostgreSQL schema through an
AshPostgres-generated logical baseline and tracked resource snapshots rather
than replaying obsolete unreleased intermediate schemas.

#### Scenario: Empty database is migrated

- **WHEN** the current migration chain runs against an empty PostgreSQL 18
  database
- **THEN** it MUST create the complete schema required by every tracked
  PostgreSQL-backed Ash resource without relying on a prior migration or local
  database state

#### Scenario: Resource schema changes

- **WHEN** a tracked Ash resource no longer matches its current resource
  snapshot and migration baseline
- **THEN** migration drift verification MUST fail until a reviewed generated
  migration and snapshot update are added

### Requirement: Baseline migrations contain schema only

Office Graph SHALL keep application records out of schema migrations and SHALL
not derive application identifiers through MD5, hashes, or handwritten SQL.

#### Scenario: Canonical application data is required

- **WHEN** capabilities, relationship definitions, endpoint rules, agent
  definitions, roles, grants, or other application records must exist
- **THEN** an owning-domain Ash setup action MUST create or reconcile them
  after schema migration

#### Scenario: Baseline source is scanned

- **WHEN** canonical verification scans the rebaselined migration chain
- **THEN** it MUST find no `execute`, SQL check body, partial-index SQL
  predicate, application-data insertion, MD5-derived identifier, or
  unapproved raw-SQL occurrence

### Requirement: Canonical setup is idempotent and Ash-owned

Office Graph SHALL expose one release-safe setup entry point that composes
idempotent owning-domain Ash setup actions for required application data.

#### Scenario: Setup runs twice

- **WHEN** release setup runs twice after migration
- **THEN** both runs MUST succeed and the second run MUST preserve the same
  logical capability, relationship-definition, endpoint-rule, and canonical
  agent-definition records without duplicates

#### Scenario: Setup resumes after a completed domain

- **WHEN** one owning domain's canonical records already exist and release
  setup runs again
- **THEN** setup MUST reconcile the remaining domains through identities and
  upserts without deleting or duplicating accepted records

### Requirement: Baseline preserves product invariants

Office Graph SHALL preserve current uniqueness, lifecycle, reference,
authorization, idempotency, and concurrency invariants when historical SQL
checks and partial indexes are removed.

#### Scenario: Historical constraint is removed

- **WHEN** the rebaseline removes an old SQL check or partial index
- **THEN** the change MUST map that invariant to typed attributes, nullability,
  foreign keys, Ash validation, atomic changes, a normal identity, or a private
  identity-slot field and MUST retain focused behavior coverage

#### Scenario: Concurrent writers target one live identity

- **WHEN** two actions concurrently create or restore the same active,
  accepted, pending, or unrevoked logical identity
- **THEN** at most one live record MUST commit and the other action MUST receive
  the owning deterministic replay or conflict outcome

### Requirement: Rebaseline requires an explicit development reset

Office Graph SHALL treat the baseline replacement as an unreleased development
reset rather than a production upgrade path.

#### Scenario: Existing local database uses old history

- **WHEN** a developer has a database migrated through the replaced chain
- **THEN** setup documentation MUST require a database or Compose-volume reset,
  or an explicit export and import, before applying the new baseline

#### Scenario: Product is released

- **WHEN** Office Graph has a supported release database history
- **THEN** future schema changes MUST use forward migrations and MUST NOT
  replace released migration history under this unreleased reset policy
