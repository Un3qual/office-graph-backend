## Why

Office Graph still carries 721 non-migration database-boundary escapes: 471
raw-SQL occurrences and 250 direct-Ecto occurrences across production code,
tests, and test support. They obscure authorization and lifecycle ownership,
encourage explicit transactions instead of Ash action transactions, make
read-modify-write races easier to introduce, and currently generate enough
debug SQL output to make the canonical test gate difficult to inspect.

## What Changes

- Replace all 92 production occurrences with Ash actions, code interfaces,
  relationships, aggregates, calculations, atomic changes, optimistic locks,
  action hooks, bulk actions, or other built-in Ash/AshPostgres behavior.
- Remove the 629 non-migration test and test-support occurrences by exercising
  public Ash/domain contracts and by replacing SQL-based fixtures, assertions,
  and concurrency controls with typed support APIs.
- Audit every mutating action that reads other persisted data and replace
  vulnerable read-modify-write sequences with atomic Ash changes, action-owned
  transactions, optimistic locking, identities/upserts, or database-enforced
  constraints.
- Silence repository and Ash SQL debug logging during normal tests while
  retaining opt-in diagnostics for debugging a failing test.
- Remove each remediated fingerprint from the canonical database-access debt
  inventory and make the normal state for non-migration code zero unapproved
  raw-SQL or direct-Ecto occurrences.
- Keep the 173 migration occurrences out of this change; the separately
  approved unreleased-migration rebaseline will replace that history and prove
  empty-database and upgrade behavior.
- Keep the single explicitly approved PostgreSQL 18 `uuidv7()` default
  fragment. No additional raw-SQL exception is approved by this change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ecto-sql-boundaries`: Require zero unapproved non-migration database
  boundary occurrences and define typed, race-safe test seams instead of
  test-authored SQL.
- `project-quality-gates`: Require quiet-by-default database logging in the
  canonical test gate with an explicit opt-in diagnostic mode.

## Impact

- Affects the 34 production files and 57 test or test-support files recorded
  under `remove-direct-database-access` in
  `openspec/specs/ecto-sql-boundaries/database-access-debt.json`.
- Changes domain commands, workers, projections, validation changes, fixture
  support, concurrency tests, and database-boundary quality checks.
- Does not change public GraphQL or JSON API contracts.
- Does not edit or rebaseline historical migrations in this change.
