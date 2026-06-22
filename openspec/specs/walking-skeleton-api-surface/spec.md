# walking-skeleton-api-surface Specification

## Purpose
TBD - created by archiving change first-backend-walking-skeleton. Update Purpose after archive.
## Requirements
### Requirement: Shared API Domain Actions
Office Graph SHALL expose GraphQL and JSON API surfaces over the same backend
domain actions.

#### Scenario: API mutation creates skeleton state
- **WHEN** a GraphQL mutation or JSON API request submits manual intake,
  applies a proposed change, links evidence, or completes verification
- **THEN** both API surfaces MUST call the same public context/domain action
  and produce equivalent authorization, validation, operation correlation,
  revision, and audit behavior

### Requirement: Minimal GraphQL Surface
Office Graph SHALL add only the GraphQL queries and mutations needed for the
walking skeleton.

#### Scenario: GraphQL client exercises the skeleton
- **WHEN** a GraphQL client bootstraps or authenticates as the local owner,
  submits intake, reviews proposed changes, applies accepted changes, adds
  evidence, and verifies completion
- **THEN** the schema MUST expose the minimum typed operations and result
  shapes needed for that flow without introducing broad projection, agent
  runtime, or provider-integration APIs

#### Scenario: GraphQL interface is introduced in the skeleton
- **WHEN** the walking skeleton introduces a shared GraphQL interface for
  graph-addressable, updatable, closable, comment-like, approvable,
  evidence-bearing, or projection-visible resources
- **THEN** the interface MUST be backed by typed resource/domain contracts and
  authorization-aware viewer affordance fields, and it MUST NOT introduce a
  generic mutation path that bypasses typed domain actions

### Requirement: Minimal JSON API Surface
Office Graph SHALL add only the JSON API endpoints needed for the walking
skeleton.

#### Scenario: JSON API client exercises the skeleton
- **WHEN** a JSON API client performs the same walking-skeleton flow as the
  GraphQL client
- **THEN** the endpoints MUST expose equivalent capabilities over shared
  domain actions without duplicating lifecycle or authorization logic

### Requirement: Authorization-Filtered Reads
Office Graph SHALL filter API reads through tenant, scope, sensitivity, and
relationship-aware authorization.

#### Scenario: Client requests graph or loop state
- **WHEN** an API client reads signals, tasks, review findings, verification
  checks, evidence, artifacts, proposed changes, or graph relationships
- **THEN** the response MUST include only records the authenticated principal
  may see, using restricted placeholders or redaction only where the active
  policy allows summary disclosure

### Requirement: API Error And Conflict Shape
Office Graph SHALL return explainable validation, authorization, idempotency,
and conflict outcomes from both API surfaces.

#### Scenario: API request cannot be applied
- **WHEN** a request fails validation, authorization, idempotency, proposed
  change validation, optimistic conflict checks, or lifecycle transition rules
- **THEN** GraphQL and JSON API responses MUST expose a structured error or
  conflict shape with enough safe detail for a client or test to understand
  the failed requirement

