# architecture-stabilization Specification

## Purpose
Define the rules for reducing architecture debt before adding broad new
features.
## Requirements
### Requirement: Stabilization Precedes Broad Feature Expansion

Office Graph SHALL complete accepted stabilization gates before adding new
broad product screens, product routes, API families, or durable workflow
concepts.

#### Scenario: Feature work touches unstable foundations

- **WHEN** proposed feature work adds GraphQL fields, JSON API endpoints,
  frontend routes, durable workflow records, or cross-domain command behavior
- **THEN** the proposal MUST identify whether the work depends on the API,
  domain, frontend, or product-concept stabilization tracks and MUST either use
  accepted stabilized patterns or add a documented exception with a retirement
  condition

#### Scenario: Narrow bug fix is needed during stabilization

- **WHEN** a bug fix is needed before a stabilization track is complete
- **THEN** the fix MAY remain narrow, but it MUST NOT copy the monolithic
  schema, scattered JSON controller, oversized component, or transport-owned
  command patterns into new product UI or API code

### Requirement: Stabilization Tracks Are Explicit

Office Graph SHALL organize architecture remediation into explicit API,
domain, frontend, and product-concept tracks.

#### Scenario: Stabilization implementation begins

- **WHEN** implementation begins for this change
- **THEN** tasks MUST identify the primary track affected and MUST include
  verification proving the change did not broaden unrelated unstable screens,
  routes, APIs, or workflows

#### Scenario: Track sequencing conflicts

- **WHEN** one stabilization track depends on another unresolved decision
- **THEN** implementation MUST resolve the dependency through OpenSpec design
  or a narrow spike before landing behavior that locks the dependent design

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

#### Scenario: Unapproved database access remains

- **WHEN** a current raw-SQL or direct-Ecto occurrence does not exactly match an
  approved exception
- **THEN** verification MUST fail until the occurrence is removed or receives
  the required exact approval through an accepted OpenSpec change, without
  consulting or rewriting a temporary debt inventory

#### Scenario: Non-SQL architecture exception is required

- **WHEN** implementation requires a custom transport, direct Ecto path without raw SQL, frontend architecture exception, or infrastructure noun exposed in a product projection
- **THEN** the exception MUST record owner, reason, approving spec, allowed scope, verification coverage, and retirement condition

### Requirement: Old Endpoints Have Retirement Conditions

Office Graph SHALL treat existing walking-skeleton and operator-console
manual endpoints as temporary unless a later accepted design promotes them to
durable product contracts.

#### Scenario: Compatibility endpoint remains in use

- **WHEN** an existing manual GraphQL field, Phoenix JSON route, serializer, or
  projection endpoint remains live during migration
- **THEN** the accepted plan MUST name the replacement endpoint or read, or the
  reason the endpoint or read remains a durable custom command/projection
  exception

#### Scenario: Compatibility endpoint is retired

- **WHEN** a compatibility endpoint is removed or redirected
- **THEN** tests MUST prove replacement GraphQL and JSON API behavior, frontend
  client behavior, authorization semantics, and structured error semantics
  remain equivalent where compatibility was promised
