## Why

The current database-boundary and migration-conformance checks grew into a broad symbolic evaluator that is difficult to reason about and still depends on interpreting source constructs that should be prohibited at this boundary. The approved direction is to keep the gate strict while replacing interpretation-heavy analysis with smaller fail-closed layers whose limits are clear.

## What Changes

- Replace the general source evaluator with four independent enforcement layers:
  - repository-wide forbidden-primitive scanning for tracked Elixir, migration, seed, test, test-support, Mix task, and SQL-like sources;
  - post-compilation dependency/import auditing from BEAM metadata;
  - built-in `mix ash_postgres.generate_migrations --check`;
  - actual terminal database-object comparison against Ash/resource ownership metadata.
- Reject dynamic migration and persistence-sensitive escape paths instead of interpreting helpers, control flow, reflection, external SQL files, raw SQL, stored routines, or direct repository calls.
- Preserve strict exact approval semantics for allowed low-level exceptions, including fingerprint invalidation, owner, reason, verification, and retirement metadata.
- Preserve the two existing approved PostgreSQL 18 UUIDv7 fragment exceptions and their provenance.
- Replace synthetic semantic analyzer tests with focused behavior tests for the new layers.
- Avoid adding repository-authored catalog SQL by using database-owned schema dump tooling for terminal database inventory.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `ecto-sql-boundaries`: Clarify that unapproved low-level database paths are prohibited by exact source/compiled gates, that approved exceptions remain exact and behavior-tested, and that dynamic or complex migration/persistence constructs fail closed.
- `project-quality-gates`: Replace symbolic database-boundary scanner requirements with the four-layer canonical gate and terminal database inventory coverage.

## Impact

Affected areas are the project-local Credo boundary check, database-boundary support modules, migration-conformance support, architecture/project-quality tests, OpenSpec specifications, and canonical verification. No product API, resource schema, dependency, migration, or repository-authored raw SQL occurrence is introduced.
