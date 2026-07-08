## ADDED Requirements

### Requirement: Product GraphQL Supports Route-Owned Frontend Operations
Office Graph SHALL treat the product GraphQL path as the frontend's primary
data and command surface and keep it compatible with route-owned operations
from Relay.

#### Scenario: Route-owned GraphQL operation is introduced
- **WHEN** a frontend route adds a product GraphQL read, mutation, or
  projection-backed command
- **THEN** the operation MUST have an owning route or capability, stable name,
  authorization-aware result shape, typed variables, safe error semantics, and
  tests that exercise the same backend projection or command contract used by
  other entrypoints

#### Scenario: Relay-backed product operation is introduced
- **WHEN** a frontend route adds a Relay-backed product GraphQL operation
- **THEN** product GraphQL reads MUST preserve stable object identity,
  connection-compatible pagination where lists can grow, fragment-friendly
  field ownership, and mutation payloads that support safe store updates or
  explicit invalidation without requiring a JSON adapter fallback

#### Scenario: Product UI asks for JSON API compatibility
- **WHEN** a product UI route can read or command workflow state through the
  product GraphQL path
- **THEN** the frontend MUST NOT add or keep a JSON API adapter for that route
  unless an accepted OpenSpec change names a current external contract,
  migration need, or data-safety reason and a retirement condition

## MODIFIED Requirements

### Requirement: Generated Ash Resource Reads Come First

Office Graph SHALL introduce generated AshGraphql and AshJsonApi resource
surfaces for safe reads before exposing generated lifecycle writes.

#### Scenario: Product frontend reads Office Graph data

- **WHEN** the React product frontend reads resource-shaped or projection data
- **THEN** it MUST use GraphQL as the normal product API, while REST/JSON API
  remains a customer integration surface and not the preferred internal UI
  transport

#### Scenario: JSON API resource reads are mounted

- **WHEN** generated AshJsonApi resource reads are exposed during stabilization
- **THEN** they MUST mount under `/api/v1`

#### Scenario: Resource surface is migrated

- **WHEN** a WorkGraph, WorkPackets, Runs, or Verification resource read is
  migrated away from manual transport code
- **THEN** the migration MUST first expose authorized generated reads or simple
  read-model actions and MUST keep lifecycle-driving creates and updates
  private unless a spec explicitly makes them public

#### Scenario: Private action exists on resource

- **WHEN** an Ash resource action is marked private or is used only by an
  owning domain command
- **THEN** GraphQL and JSON API generation MUST NOT expose that action merely
  because the resource has AshGraphql or AshJsonApi extensions
