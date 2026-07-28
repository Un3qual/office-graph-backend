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
