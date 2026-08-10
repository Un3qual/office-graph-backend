## MODIFIED Requirements

### Requirement: Approved Direct SQL Paths
Office Graph SHALL prohibit repository-authored raw SQL, SQL fragments, unsafe
fragments, direct SQL query calls, SQL-bearing migration execution, tracked SQL
files, direct repository calls, and low-level persistence primitives unless the
user explicitly approves the exact occurrence through an accepted OpenSpec
change. Broad categories such as projection, replay, analytics, reconciliation,
migration, test setup, catalog inspection, or bulk work SHALL NOT constitute
approval.

Direct Ecto or explicit `Repo.transaction` paths that contain no raw SQL MUST
still prefer built-in Ash and AshPostgres behavior and MUST document the exact
missing framework capability before remaining as an accepted architecture
exception.

#### Scenario: An Ash feature can express the behavior
- **WHEN** an action, code interface, relationship, managed relationship, identity, aggregate, built-in validation or change, atomic change, optimistic lock, hook, generic action, or action-managed transaction can express required behavior safely
- **THEN** the implementation MUST use that Ash feature instead of direct Ecto or raw SQL

#### Scenario: Raw SQL appears necessary
- **WHEN** evidence shows that built-in Ash, AshPostgres, declarative Ecto migration behavior, or database-owned inspection tooling cannot express a required database operation safely
- **THEN** implementation MUST stop until the user approves the exact SQL occurrence in an accepted OpenSpec change

#### Scenario: User approves an exact SQL occurrence
- **WHEN** an accepted OpenSpec change explicitly approves repository-authored SQL
- **THEN** the exception MUST identify its occurrence fingerprint, file, owner, reason, verification coverage, and retirement condition

#### Scenario: Direct Ecto appears necessary without raw SQL
- **WHEN** a safe requirement cannot be expressed through built-in Ash behavior but can be expressed through typed Ecto constructs without SQL strings
- **THEN** the accepted OpenSpec design MUST document the missing Ash capability, bounded scope, verification, and retirement condition

#### Scenario: Catalog SQL appears necessary
- **WHEN** implementation needs repository-authored catalog SQL for inspection or verification
- **THEN** work MUST pause until the exact SQL text, fingerprint, owner, reason, verification coverage, and retirement condition are approved through OpenSpec

### Requirement: Non-migration database access is fully approved

Office Graph SHALL have zero unapproved raw-SQL, direct-Ecto, direct repository,
or low-level persistence-primitive occurrences in runtime code, tests, test
support, Mix tasks, scripts, tracked SQL-like files, or seeds. Explicitly
approved exceptions SHALL remain exact and fingerprinted.

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

#### Scenario: Approved inventory repeats one locator

- **WHEN** two approved entries share the same path, line, class, construct,
  function, and ordinal even when their fingerprints differ
- **THEN** canonical verification MUST reject the approved inventory before
  matching current fingerprints or suppressing stale entries

#### Scenario: Approval provenance is invalid

- **WHEN** an approved exception references a missing change directory, a
  missing or invalid approval-evidence file, an unmatched approval record, or
  multiple archived directories for the same approving change
- **THEN** canonical verification MUST reject the approved inventory before
  matching current fingerprints or suppressing stale entries

#### Scenario: Framework capability is insufficient

- **WHEN** implementation cannot safely express one exact occurrence through
  the pinned Ash and AshPostgres versions
- **THEN** work on that occurrence MUST stop until a later accepted OpenSpec
  change records the exact fingerprint and explicit user approval

#### Scenario: Approved low-level exception is behavior-sensitive

- **WHEN** an exact approved exception can affect data-plane behavior,
  authorization, locking, session state, notification, stored routine behavior,
  or transient write behavior
- **THEN** the accepted change MUST include focused behavior tests in addition
  to schema comparison

### Requirement: Migration baseline has no removal debt

Office Graph SHALL have zero unapproved raw-SQL, direct-database, direct
repository, dynamic migration, or complex migration occurrences in its terminal
migration baseline. The baseline MAY retain only exact user-approved,
fingerprinted migration exceptions whose accepted OpenSpec change proves
declarative AshPostgres and Ecto migration behavior is insufficient.

#### Scenario: Terminal migration baseline is scanned

- **WHEN** canonical verification scans the current migration baseline
- **THEN** every detected occurrence MUST match an exact explicitly approved
  exception and every approved migration exception MUST still match current
  source

#### Scenario: Generated migration includes SQL

- **WHEN** AshPostgres generation emits an SQL-bearing check, predicate,
  execute call, fragment, or other raw-SQL construct not already approved
  exactly
- **THEN** implementation MUST replace it with typed declarative behavior or
  stop until the user approves that exact occurrence in the active change

#### Scenario: Native UUIDv7 default remains necessary

- **WHEN** the PostgreSQL 18 `uuidv7()` default remains represented by a
  previously approved generated fragment
- **THEN** the approved-exception inventory MUST retain its exact path and
  fingerprint while preserving the original reason, verification, and
  retirement condition

#### Scenario: Migration uses dynamic or complex behavior

- **WHEN** a migration uses helpers, arbitrary control flow,
  environment-dependent branches, reflection, external SQL files, raw SQL,
  procedures, functions, triggers, DO blocks, direct repository calls, or
  unresolved database-shaped variable calls
- **THEN** canonical verification MUST fail closed instead of interpreting the
  migration to prove terminal ownership

## ADDED Requirements

### Requirement: Stored database behavior is prohibited by default

Office Graph SHALL prohibit project-owned database functions, procedures,
ordinary, constraint, and event triggers, views, materialized views, RLS
policies and table enable/force state, grants, and extensions unless an accepted
OpenSpec change approves the exact source occurrence and terminal database
object.

#### Scenario: Stored routine is introduced
- **WHEN** canonical verification finds a project-owned terminal function,
  procedure, trigger, view, materialized view, RLS policy, grant, or extension
  without exact approval
- **THEN** verification MUST fail and identify the object class and name

#### Scenario: Approved stored behavior exists
- **WHEN** an approved stored database behavior exists
- **THEN** its source occurrence fingerprint, terminal object identity and
  definition fingerprint,
  behavior tests, owner, reason, verification, and retirement condition MUST
  all remain current
