## REMOVED Requirements

### Requirement: Existing Database Access Is Removal Debt

**Reason**: The accepted remediation completed and the inventory contains no occurrences, so inventory generation and remediation-progress behavior no longer enforce a live repository state.

**Migration**: Canonical verification now compares every current occurrence directly with the exact approved-exception inventory and rejects every unmatched occurrence.

## MODIFIED Requirements

### Requirement: Non-migration database access has no removal debt

Office Graph SHALL have zero unapproved raw-SQL or direct-Ecto occurrences in
runtime code, tests, test support, or seeds. Explicitly approved exceptions
SHALL remain exact and fingerprinted.

#### Scenario: Non-migration source is scanned

- **WHEN** canonical verification scans a tracked source outside
  `priv/repo/migrations`
- **THEN** every database interaction MUST use an owning Ash resource, action,
  relationship, aggregate, calculation, query lock, atomic change, bulk API, or
  other built-in Ash/AshPostgres interface

#### Scenario: Terminal repository scan completes

- **WHEN** canonical verification scans the current repository
- **THEN** every detected occurrence MUST match an exact explicitly approved
  exception or fail without consulting or rewriting a temporary debt inventory

#### Scenario: Framework capability is insufficient

- **WHEN** implementation cannot safely express one exact occurrence through
  the pinned Ash and AshPostgres versions
- **THEN** work on that occurrence MUST stop until a later accepted OpenSpec
  change records the exact fingerprint and explicit user approval

### Requirement: Tests use typed persistence boundaries

Office Graph tests SHALL create, mutate, coordinate, assert, and clean persisted
state through public Ash/domain behavior or narrow test-only typed seams rather
than SQL, direct Ecto, catalog inspection, database-object mutation, or a shadow
copy of the product resource graph.

#### Scenario: Test needs otherwise unreachable state

- **WHEN** a behavior test needs a lifecycle or failure state that public
  product input cannot reach directly
- **THEN** test support MUST use a test-owned Ash action, canonical-resource
  data-layer seam, or process-scoped adapter that MUST NOT update the row with
  Repo or SQL

#### Scenario: Committed concurrency data is cleaned

- **WHEN** independent database owners commit records that outlive the SQL
  sandbox transaction
- **THEN** cleanup MUST select canonical Ash resources and hard-delete them
  through one test-only Ash seam without redeclaring their tables, attributes,
  or domain

#### Scenario: Test proves a database constraint

- **WHEN** a test needs to prove uniqueness, scope, lifecycle, or referential
  integrity
- **THEN** it MUST exercise the owning action and assert its typed outcome
  instead of reading PostgreSQL catalogs or issuing invalid SQL directly

#### Scenario: Test coordinates concurrent writers

- **WHEN** a concurrency test must pause or order independent transactions
- **THEN** it MUST coordinate at a typed action/adapter seam with independent
  sandbox owners and MUST NOT create triggers, functions, advisory locks, or
  renamed tables
