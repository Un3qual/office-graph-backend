## ADDED Requirements

### Requirement: Stabilization Precedes Broad Feature Expansion

Office Graph SHALL complete accepted stabilization gates before adding new
broad product surfaces, new API families, or new durable workflow concepts.

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
  command patterns into new product surface area

### Requirement: Stabilization Tracks Are Explicit

Office Graph SHALL organize architecture remediation into explicit API,
domain, frontend, and product-concept tracks.

#### Scenario: Stabilization implementation begins

- **WHEN** implementation begins for this change
- **THEN** tasks MUST identify the primary track affected and MUST include
  verification proving the change did not broaden unrelated unstable surfaces

#### Scenario: Track sequencing conflicts

- **WHEN** one stabilization track depends on another unresolved decision
- **THEN** implementation MUST resolve the dependency through OpenSpec design
  or a narrow spike before landing behavior that locks the dependent design

### Requirement: Architecture Drift Gates

Office Graph SHALL include verification gates that fail when new architecture
debt is added without accepted documentation.

#### Scenario: Verification runs

- **WHEN** backend, frontend, or full project verification runs
- **THEN** the gate MUST check for undocumented manual API surfaces, direct
  database exceptions, broad `authorize?: false` paths, missing frontend build
  verification, and OpenSpec drift relevant to the stabilization tracks

#### Scenario: New exception is required

- **WHEN** implementation requires a custom transport, direct database access,
  frontend architecture exception, or infrastructure noun exposed in a product
  projection
- **THEN** the exception MUST record owner, reason, approving spec, allowed
  scope, verification coverage, and retirement condition

### Requirement: Compatibility Surfaces Have Retirement Conditions

Office Graph SHALL treat existing walking-skeleton and operator-console
compatibility surfaces as temporary unless a later accepted design promotes
them to durable product contracts.

#### Scenario: Compatibility endpoint remains in use

- **WHEN** an existing manual GraphQL field, Phoenix JSON route, serializer, or
  projection endpoint remains live during migration
- **THEN** the accepted plan MUST name the replacement surface or the reason the
  surface remains a durable custom command/projection exception

#### Scenario: Compatibility endpoint is retired

- **WHEN** a compatibility endpoint is removed or redirected
- **THEN** tests MUST prove replacement GraphQL and JSON API behavior, frontend
  client behavior, authorization semantics, and structured error semantics
  remain equivalent where compatibility was promised
