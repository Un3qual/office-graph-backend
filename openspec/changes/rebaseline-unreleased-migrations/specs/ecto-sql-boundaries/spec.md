## ADDED Requirements

### Requirement: Migration baseline has no removal debt

Office Graph SHALL have zero unapproved raw-SQL or direct-database debt in its
terminal migration baseline. The baseline MAY retain only exact
user-approved, fingerprinted migration exceptions whose accepted OpenSpec
change proves declarative AshPostgres and Ecto migration behavior is
insufficient.

#### Scenario: Rebaseline change completes

- **WHEN** `rebaseline-unreleased-migrations` is ready to archive
- **THEN** the debt inventory MUST contain zero entries assigned to that
  change and MUST contain no stale path from the replaced migration chain

#### Scenario: Generated migration includes SQL

- **WHEN** AshPostgres generation emits an SQL-bearing check, predicate,
  execute call, fragment, or other raw-SQL construct not already approved
  exactly
- **THEN** implementation MUST replace it with typed declarative behavior or
  stop until the user approves that exact occurrence in the active change

#### Scenario: Native UUIDv7 default remains necessary

- **WHEN** the PostgreSQL 18 `uuidv7()` default remains represented by the
  previously approved generated fragment
- **THEN** the approved-exception inventory MUST update its exact path and
  fingerprint to the baseline occurrence while preserving the original
  reason, verification, and retirement condition
