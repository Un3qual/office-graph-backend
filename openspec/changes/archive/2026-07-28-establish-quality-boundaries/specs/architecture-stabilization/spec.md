## MODIFIED Requirements

### Requirement: Architecture Drift Gates

Office Graph SHALL include verification gates that fail when parallel planning,
unapproved raw SQL, unclassified direct Ecto, manual API debt, broad
authorization bypasses, or other architecture debt is added without accepted
OpenSpec documentation.

#### Scenario: Verification runs

- **WHEN** backend, frontend, or full project verification runs
- **THEN** the gate MUST check for parallel planning artifacts, undocumented manual API endpoints, unapproved raw SQL, unclassified direct database access, broad `authorize?: false` paths, missing frontend build verification, dependency advisories, and OpenSpec drift relevant to the stabilization tracks

#### Scenario: Full project verification runs

- **WHEN** a developer or CI runs the named full-project verification or precommit alias
- **THEN** the gate MUST compile the backend once with warnings as errors, run the complete backend test suite exactly once, validate the current Relay schema and frontend build, check locked dependencies for published advisories, validate planning and database-boundary inventories, and run strict validation for checked-in OpenSpec specs and changes

#### Scenario: New raw SQL is proposed

- **WHEN** implementation proposes a SQL query, fragment, unsafe fragment, migration execution, SQL-bearing DDL option, or tracked SQL file
- **THEN** the exact occurrence MUST receive explicit user approval in an accepted OpenSpec change before implementation

#### Scenario: Existing database debt remains

- **WHEN** an existing raw-SQL or direct-Ecto occurrence has not yet been removed
- **THEN** it MUST remain in the temporary debt inventory with an owning remediation change and MUST NOT be represented as an approved exception

#### Scenario: Non-SQL architecture exception is required

- **WHEN** implementation requires a custom transport, direct Ecto path without raw SQL, frontend architecture exception, or infrastructure noun exposed in a product projection
- **THEN** the exception MUST record owner, reason, approving spec, allowed scope, verification coverage, and retirement condition
