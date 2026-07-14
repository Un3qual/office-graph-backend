## ADDED Requirements

### Requirement: Relationship Definitions Are Relational And Canonical
Office Graph SHALL store each accepted relationship definition as a typed,
migration-owned record with stable key, family, direction, meaning, lifecycle,
provenance, authorization, cycle, and specialization posture.

#### Scenario: MVP vocabulary is installed
- **WHEN** the relationship registry migration runs in a new environment
- **THEN** every accepted MVP relationship key MUST exist without requiring an
  application seed

#### Scenario: Unknown definition is requested
- **WHEN** a command requests a relationship key that is not registered
- **THEN** Office Graph MUST reject the command without creating an edge or a
  generic fallback definition

### Requirement: Endpoint Compatibility Is Typed
Office Graph SHALL store allowed source and target graph-item kinds as relational
endpoint rules for each relationship definition.

#### Scenario: Compatible endpoints are supplied
- **WHEN** a relationship command supplies source and target item kinds allowed
  by the canonical definition
- **THEN** endpoint compatibility validation MUST succeed without reading JSON
  metadata or provider-specific code

#### Scenario: Incompatible endpoints are supplied
- **WHEN** either endpoint kind is not allowed by the canonical definition
- **THEN** the command MUST return a stable validation error and MUST NOT create
  the relationship

### Requirement: Registry Administration Is Not A Product Surface
Office Graph SHALL change the canonical MVP registry only through reviewed
migrations while relationship governance administration remains out of scope.

#### Scenario: API client attempts to create a definition
- **WHEN** a GraphQL or JSON API client attempts to create, update, or delete a
  relationship definition
- **THEN** Office Graph MUST expose no generic registry mutation
