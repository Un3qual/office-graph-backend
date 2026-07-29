## ADDED Requirements

### Requirement: Non-migration database access has no removal debt

Office Graph SHALL have zero unapproved raw-SQL or direct-Ecto occurrences in
runtime code, tests, test support, or seeds after this change. Historical
migration debt SHALL remain isolated to the dedicated unreleased-migration
rebaseline, and explicitly approved exceptions SHALL remain exact and
fingerprinted.

#### Scenario: Non-migration source is scanned

- **WHEN** canonical verification scans a tracked source outside
  `priv/repo/migrations`
- **THEN** every database interaction MUST use an owning Ash resource, action,
  relationship, aggregate, calculation, query lock, atomic change, bulk API, or
  other built-in Ash/AshPostgres interface

#### Scenario: Removal change completes

- **WHEN** `remove-direct-database-access` is ready to archive
- **THEN** the debt inventory MUST contain zero entries assigned to that change
  and the approved inventory MUST contain no exception added by this change

#### Scenario: Framework capability is insufficient

- **WHEN** implementation cannot safely express one exact occurrence through
  the pinned Ash and AshPostgres versions
- **THEN** work on that occurrence MUST stop until a later accepted OpenSpec
  change records the exact fingerprint and explicit user approval

### Requirement: Tests use typed persistence boundaries

Office Graph tests SHALL create, mutate, coordinate, and assert persisted state
through public Ash/domain behavior or narrow test-only typed seams rather than
SQL, direct Ecto, catalog inspection, or database-object mutation.

#### Scenario: Test needs otherwise unreachable state

- **WHEN** a behavior test needs a lifecycle or failure state that public
  product input cannot reach directly
- **THEN** test support MUST use a test-only Ash action or adapter seam that
  retains resource validation and MUST NOT update the row with Repo or SQL

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

### Requirement: Mutating actions prevent read-modify-write races

Office Graph SHALL make every mutating action that reads persisted data before
writing enforce its invariant in the owning Ash action transaction using
atomic changes, optimistic locking, identities/upserts, query locks, managed
relationships, or database constraints.

#### Scenario: Two writers use the same expected version

- **WHEN** two concurrent commands derive a write from the same versioned
  record
- **THEN** at most one command MUST commit and the other MUST receive the
  owning typed conflict without overwriting the winner

#### Scenario: Two writers create the same logical identity

- **WHEN** concurrent commands target one idempotency, replay, provider, or
  aggregate identity
- **THEN** the identity/upsert contract MUST produce one logical record and
  deterministic replay or conflict behavior

#### Scenario: Child state changes an aggregate

- **WHEN** a child record changes parent lifecycle, execution, readiness, or
  verification state
- **THEN** the parent update MUST be atomic with the accepted child transition
  or recomputed from committed children without a stale read followed by an
  unconditional write
