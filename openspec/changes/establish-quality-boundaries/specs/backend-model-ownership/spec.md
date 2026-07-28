## MODIFIED Requirements

### Requirement: Direct Ecto Exception Control

Office Graph SHALL treat direct Ecto outside Ash-managed domain actions as
unapproved removal debt unless an accepted OpenSpec change documents the exact
missing Ash capability and bounded typed-Ecto exception. Repository-authored
raw SQL is prohibited unless the user explicitly approves the exact occurrence
in an accepted OpenSpec change.

#### Scenario: Existing direct database access remains

- **WHEN** a current direct-Ecto or raw-SQL occurrence has not received exact approval under the new boundary
- **THEN** it MUST appear only in the machine-readable removal-debt inventory with an owner and remediation change

#### Scenario: A normal mutation is implemented

- **WHEN** production code creates, updates, or deletes a durable domain record
- **THEN** it MUST use the owning Ash action, code interface, managed relationship, bulk action, or generic action rather than direct Ecto

### Requirement: Architecture Gate Covers Model Ownership

The backend verification gate SHALL fail when implementation, model ownership,
the database-access debt inventory, or the exact approved-exception inventory
diverge.

#### Scenario: Backend verification runs

- **WHEN** canonical project verification runs
- **THEN** it MUST verify table inventory, Ash domain and resource registration, absence of duplicate table-backed Ecto schemas, planned resource coverage, and exact non-growth of database-access debt

### Requirement: Exception Ledger Is A Burn-Down Contract

Office Graph SHALL distinguish unapproved database-access removal debt from
accepted non-SQL architecture exceptions and explicitly approved raw-SQL
occurrences.

#### Scenario: Existing database debt is touched

- **WHEN** code covered by a database-access debt entry is moved, rewritten, broadened, or removed
- **THEN** verification MUST reject the stale or changed fingerprint until the same change removes or updates the debt through its owning remediation

#### Scenario: Database debt is retired

- **WHEN** a direct database, raw SQL, broad `authorize?: false`, or manual transaction path is replaced
- **THEN** tests MUST prove the replacement preserves or strengthens authorization, idempotency, concurrency, operation correlation, audit and revision behavior, and partial-commit safety

### Requirement: New Direct Database Paths Require Coverage

Office Graph SHALL reject new direct-Ecto occurrences by default and SHALL
reject every new repository-authored raw-SQL occurrence until the user
explicitly approves that exact occurrence in an accepted OpenSpec change.

#### Scenario: A direct-Ecto path is proposed

- **WHEN** implementation proposes direct Ecto without handwritten SQL
- **THEN** the design MUST first exhaust built-in Ash and AshPostgres behavior and document the exact missing capability before an exception can be accepted

#### Scenario: A raw-SQL occurrence is proposed

- **WHEN** implementation proposes a SQL query, fragment, unsafe fragment, migration execution, SQL-bearing DDL option, or tracked SQL file
- **THEN** implementation MUST stop until the user explicitly approves the exact occurrence and its verification and retirement metadata in OpenSpec
