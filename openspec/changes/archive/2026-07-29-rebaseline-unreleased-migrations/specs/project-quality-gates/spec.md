## ADDED Requirements

### Requirement: Canonical verification proves migration baseline integrity

Canonical verification SHALL prove that AshPostgres resources, tracked
snapshots, the current migration baseline, and required application setup
remain synchronized and usable on PostgreSQL 18.

#### Scenario: Resource and snapshot drift check runs

- **WHEN** the canonical gate validates the migration baseline
- **THEN** it MUST run AshPostgres migration generation in non-mutating check
  mode and fail on resource or snapshot drift

#### Scenario: Fresh baseline check runs

- **WHEN** canonical verification starts its isolated PostgreSQL 18 service
- **THEN** it MUST migrate an empty scratch database, run release setup twice,
  and verify representative Ash reads without running the complete ExUnit
  suite a second time

#### Scenario: Baseline verification succeeds

- **WHEN** migration drift and fresh baseline/setup checks pass from a clean
  checkout
- **THEN** the checks MUST leave the worktree clean and MUST NOT rewrite a
  migration, resource snapshot, inventory, or OpenSpec artifact
