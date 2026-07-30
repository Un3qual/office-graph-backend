# ecto-sql-boundaries Specification

## Purpose
Define the narrow, documented cases where direct Ecto or SQL access is permitted.
## Requirements
### Requirement: Approved Direct SQL Paths
Office Graph SHALL prohibit repository-authored raw SQL, SQL fragments, unsafe
fragments, direct SQL query calls, SQL-bearing migration execution, and tracked
SQL files unless the user explicitly approves the exact occurrence through an
accepted OpenSpec change. Broad categories such as projection, replay,
analytics, reconciliation, migration, test setup, or bulk work SHALL NOT
constitute approval.

Direct Ecto or explicit `Repo.transaction` paths that contain no raw SQL MUST
still prefer built-in Ash and AshPostgres behavior and MUST document the exact
missing framework capability before remaining as an accepted architecture
exception.

#### Scenario: An Ash feature can express the behavior
- **WHEN** an action, code interface, relationship, managed relationship, identity, aggregate, built-in validation or change, atomic change, optimistic lock, hook, generic action, or action-managed transaction can express required behavior safely
- **THEN** the implementation MUST use that Ash feature instead of direct Ecto or raw SQL

#### Scenario: Raw SQL appears necessary
- **WHEN** evidence shows that built-in Ash, AshPostgres, and declarative Ecto migration behavior cannot express a required database operation safely
- **THEN** implementation MUST stop until the user approves the exact SQL occurrence in an accepted OpenSpec change

#### Scenario: User approves an exact SQL occurrence
- **WHEN** an accepted OpenSpec change explicitly approves repository-authored SQL
- **THEN** the exception MUST identify its occurrence fingerprint, file, owner, reason, verification coverage, and retirement condition

#### Scenario: Direct Ecto appears necessary without raw SQL
- **WHEN** a safe requirement cannot be expressed through built-in Ash behavior but can be expressed through typed Ecto constructs without SQL strings
- **THEN** the accepted OpenSpec design MUST document the missing Ash capability, bounded scope, verification, and retirement condition

### Requirement: Direct Query Authorization Inputs
Any explicitly approved raw-SQL or accepted direct-Ecto read path MUST accept
tenant, scope, actor, authorization, sensitivity, soft-delete, and operation
context inputs required by the records it reads. Approval of a database access
mechanism SHALL NOT bypass product authorization or lifecycle requirements.

#### Scenario: An approved direct read returns product data
- **WHEN** an approved exception returns graph nodes, edges, artifacts, conversations, summaries, counts, revisions, or other product records
- **THEN** it MUST apply the owning domain's authorization and in-table soft-deletion semantics before data reaches the caller

#### Scenario: An approved read crosses a domain boundary
- **WHEN** an approved direct read needs data owned by another domain
- **THEN** it MUST use an accepted typed interface or result contract and MUST NOT expose arbitrary database rows

### Requirement: Direct Mutation Safeguards
Raw-SQL mutation SHALL have no standing permission in Office Graph. An
explicitly approved raw-SQL mutation or accepted direct-Ecto mutation MUST be
domain-owned, operation-correlated, authorized, atomic, race-tested, and subject
to the same revision, audit, soft-deletion, event, and idempotency expectations
as an Ash action.

#### Scenario: A bulk or reconciliation mutation is proposed
- **WHEN** a bulk, provider-sync, bootstrap, maintenance, or reconciliation path needs to mutate persisted data
- **THEN** the implementation MUST first use Ash bulk actions, upserts, managed relationships, generic actions, or action-managed transactions

#### Scenario: An approved direct mutation runs
- **WHEN** an exact direct mutation exception has been accepted
- **THEN** tests MUST prove authorization, operation correlation, idempotency, concurrency behavior, revision and audit behavior, and failure atomicity

#### Scenario: A schema migration needs data initialization
- **WHEN** capabilities, roles, reference rows, bootstrap state, or other application data must be initialized
- **THEN** the data MUST be created through an Ash-owned setup or release workflow rather than inserted through a schema migration unless the exact SQL is explicitly approved

### Requirement: Read Model Ownership
Read models and projections SHALL be represented through Ash resources, read
actions, relationships, aggregates, calculations, manual relationships, or
typed generic actions whenever those mechanisms can express the query safely.
Any approved lower-level read model MUST have an explicit owning domain and
typed result contract.

#### Scenario: A mixed-resource projection is introduced
- **WHEN** a read combines graph, authorization, content, evidence, external-reference, and run data
- **THEN** the owning domain MUST first model the projection through Ash reads and typed relationships rather than arbitrary row maps

#### Scenario: A caller needs private columns
- **WHEN** an entrypoint requests fields from another domain's private tables
- **THEN** the owning domain MUST expose an approved action, relationship, or typed query result instead of allowing the caller to query the private table

### Requirement: Existing Database Access Is Removal Debt
Office Graph SHALL record existing raw-SQL and direct-Ecto occurrences that
have not received exact user approval as temporary removal debt and SHALL NOT
describe them as approved architecture.

#### Scenario: The initial debt inventory is created
- **WHEN** this quality boundary is implemented against the existing repository
- **THEN** every existing occurrence MUST receive a deterministic fingerprint, construct class, owner, and future remediation change without receiving implied approval

#### Scenario: A later remediation change lands
- **WHEN** a later change replaces an inventoried occurrence with built-in Ash or declarative migration behavior
- **THEN** that change MUST remove the matching debt entry and preserve or strengthen behavioral and concurrency verification

#### Scenario: A debt occurrence changes
- **WHEN** an inventoried occurrence is moved, rewritten, or broadened before removal
- **THEN** verification MUST treat the changed fingerprint as a new unapproved occurrence

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
