# walking-skeleton-api-surface Specification

## Purpose

Define the walking-skeleton API endpoints: minimal GraphQL command endpoints
and generated JSON resource reads that share domain logic, preserve
authorization and operation context, expose only the loop needed for skeleton
verification, and return explainable diagnostic error or conflict shapes.

## Requirements

### Requirement: Shared API Domain Actions

Office Graph SHALL route GraphQL and JSON API endpoints through the same
backend domain actions when both transports currently expose the same command or
read. JSON parity applies only to generated `/api/v1` resource reads or
explicitly documented custom JSON exceptions.

#### Scenario: API mutation creates skeleton state

- **WHEN** a GraphQL mutation submits manual intake, applies proposed graph
  changes, links evidence, completes verification, or runs the current
  packet-run verification command
- **THEN** it MUST call the public context/domain action and produce the
  expected authorization, validation, operation correlation, revision, and audit
  behavior
- **AND WHEN** a generated JSON API resource read exposes the same current
  resource data
- **THEN** that read MUST use the same persisted domain state and authorization
  rules without requiring a duplicate custom JSON command endpoint

### Requirement: Minimal GraphQL API

Office Graph SHALL add only the GraphQL queries and mutations needed for the
walking skeleton.

#### Scenario: GraphQL client exercises the skeleton

- **WHEN** a GraphQL client bootstraps or authenticates as the local owner,
  submits intake, reviews proposed graph changes, applies accepted changes, adds
  evidence, and verifies completion
- **THEN** the schema MUST expose the minimum typed operations and result
  shapes needed for that flow without introducing broad projection, agent
  runtime, or provider-integration APIs

#### Scenario: GraphQL interface is introduced in the skeleton

- **WHEN** the walking skeleton introduces a shared GraphQL interface for
  graph-addressable, updatable, closable, comment-like, approvable,
  evidence-bearing, or projection-visible resources
- **THEN** the interface MUST be backed by typed resource/domain contracts and
  authorization-aware viewer action fields, and it MUST NOT introduce a
  generic mutation path that bypasses typed domain actions

### Requirement: Minimal JSON API

Office Graph SHALL keep JSON API coverage to generated `/api/v1` resource reads
and explicitly documented custom exceptions.

#### Scenario: JSON API client exercises the skeleton

- **WHEN** a JSON API client reads current walking-skeleton resources
- **THEN** the generated `/api/v1` endpoints MUST expose those resources over
  shared persisted domain state without duplicating lifecycle command logic

### Requirement: Authorization-Filtered Reads

Office Graph SHALL filter API reads through tenant, scope, sensitivity, and
relationship-aware authorization.

#### Scenario: Client requests graph or loop state

- **WHEN** an API client reads signals, tasks, review findings, verification
  checks, evidence, artifacts, proposed graph changes, or graph relationships
- **THEN** the response MUST include only records the authenticated principal
  may see, using restricted placeholders or redaction only where the active
  policy allows summary disclosure

### Requirement: API Error And Conflict Shape

Office Graph SHALL return explainable validation, authorization, idempotency,
and conflict outcomes from each current API endpoint.

#### Scenario: API request cannot be applied

- **WHEN** a request fails validation, authorization, idempotency, proposed
  graph change validation, optimistic conflict checks, or lifecycle
  transition rules
- **THEN** the active API response MUST expose a structured error or conflict
  shape with enough safe detail for a client or test to understand the failed
  requirement
