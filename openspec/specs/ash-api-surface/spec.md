# ash-api-surface Specification

## Purpose

Define the durable GraphQL and JSON API posture for Ash-owned Office Graph
resources and actions.

## Requirements

### Requirement: Ash API Packages Are The Default

Office Graph SHALL expose Ash-owned resources and actions through AshGraphql
and AshJsonApi by default rather than hand-rolled GraphQL object trees or
Phoenix JSON controllers.

#### Scenario: Ash resource is exposed through GraphQL or JSON API

- **WHEN** an Ash resource, Ash action, or Ash domain-owned query becomes part
  of a product API surface
- **THEN** the implementation plan MUST first use AshGraphql and AshJsonApi
  declarations on the owning domain/resource or document why that surface is a
  valid custom transport exception

#### Scenario: Resource API shape needs transport-specific presentation

- **WHEN** GraphQL or JSON API needs field naming, pagination, filtering,
  sorting, error presentation, or relationship shape that differs by transport
- **THEN** the transport layer MAY add mapping code, but the underlying action,
  authorization, validation, operation correlation, revision, audit, and
  lifecycle behavior MUST remain owned by the Ash resource/domain or public
  context contract

### Requirement: Walking Skeleton Manual API Is Quarantined

Office Graph SHALL treat the existing hand-written walking-skeleton GraphQL and
JSON transport code as temporary smoke-test code that must not spread to new
product API surfaces.

#### Scenario: New API work touches walking-skeleton endpoints

- **WHEN** future API work extends manual intake, change proposal application,
  verification completion, or walking-skeleton read behavior
- **THEN** the work MUST either migrate the surface to AshGraphql/AshJsonApi or
  explicitly keep the manual code isolated as a temporary compatibility path
  with a cleanup task

#### Scenario: Developer adds a new product API operation

- **WHEN** a developer needs a new product GraphQL mutation, JSON API endpoint,
  resource read, projection, or workflow command
- **THEN** they MUST NOT copy the monolithic `OfficeGraphWeb.Schema`,
  `WalkingSkeletonController`, or manual serializer pattern as the default
  architecture

#### Scenario: Walking-skeleton smoke tests remain useful

- **WHEN** smoke tests still need to exercise the original walking-skeleton
  loop before the product API migration is complete
- **THEN** the tests MAY keep using the temporary endpoints, but must not be
  used as evidence that manual transport code is the accepted long-term API
  implementation pattern

### Requirement: Custom Transport Code Is Exception-Based

Office Graph SHALL allow custom Absinthe or Phoenix transport code only for
orchestration commands, projections, or transport-specific envelopes that do
not map cleanly to generated Ash APIs.

#### Scenario: Orchestration command spans domains

- **WHEN** a GraphQL mutation or JSON route coordinates multiple domains such
  as intake, change proposals, verification, work packets, runs, or agent
  runtime activity
- **THEN** custom transport code MAY exist as a thin entrypoint that builds or
  receives operation context, calls public domain commands, maps errors, and
  avoids owning business rules

#### Scenario: Custom endpoint bypasses generated APIs

- **WHEN** a design proposes custom transport code for a resource or action
  that AshGraphql or AshJsonApi could expose directly
- **THEN** the design MUST record the reason, cleanup condition if temporary,
  and tests proving shared authorization and lifecycle semantics with the
  owning Ash action

### Requirement: GraphQL Schema Is Modular

Office Graph SHALL keep GraphQL schema growth modular by domain, capability,
or generated Ash schema contribution rather than concentrating product schema
definitions in one large manually maintained file.

#### Scenario: Domain adds GraphQL API surface

- **WHEN** a bounded context adds GraphQL types, fields, mutations,
  subscriptions, interfaces, or unions
- **THEN** schema ownership MUST live with the owning context, Ash resource, or
  API capability module, and the root schema MUST compose those modules rather
  than accumulating all definitions inline

#### Scenario: Capability interface is exposed

- **WHEN** GraphQL exposes shared interfaces such as closable, updatable,
  approvable, subscribable, projection-capable, comment-like, or reactable
  behavior
- **THEN** the interface implementation MUST use typed resource/domain
  contracts and viewer-aware authorization affordances rather than generic
  mutation paths or table-type switches

### Requirement: JSON API Uses AshJsonApi For Resource Surfaces

Office Graph SHALL use AshJsonApi for JSON API resource surfaces unless a
documented integration or workflow requirement needs a custom command endpoint.

#### Scenario: Client reads or mutates a resource collection

- **WHEN** JSON API exposes resource reads, resource relationships, create,
  update, delete, filtering, sorting, or pagination for Ash-owned data
- **THEN** the surface MUST be planned as AshJsonApi-backed unless accepted
  design documents a custom exception

#### Scenario: Integration-friendly command endpoint is required

- **WHEN** an external integration, webhook-style flow, export, or workflow
  command needs a JSON endpoint that is not a natural resource action
- **THEN** the custom Phoenix endpoint MUST stay thin and call the same public
  context/domain command that GraphQL, jobs, agents, and other entrypoints use

### Requirement: Packet Run Verification Slice Uses Shared Domain APIs

Office Graph SHALL expose the first packet-run-verification slice through
shared domain actions and Ash-owned API surfaces.

#### Scenario: Resource surface is exposed

- **WHEN** packet versions, work runs, execution observations, evidence
  candidates, accepted evidence, or verification results are exposed for API
  reads or simple resource mutations
- **THEN** the implementation MUST use AshGraphql and AshJsonApi declarations
  on the owning domain/resource or document a narrow custom transport
  exception

#### Scenario: Domain-owned packet-run and evidence creates are not exposed as simple resource creates

- **WHEN** packet creation, packet-version readiness, packet source links,
  packet required-check links, work-run lifecycle, run required checks,
  execution observations, evidence candidates, or accepted evidence require
  command-owned derivation, operation validation, idempotency,
  evidence-acceptance rules, or packet-contract checks
- **THEN** Office Graph MUST keep those create actions private to the owning
  domain command and MUST not expose generated public resource creates that let
  callers choose lifecycle state, candidate state, accepted-evidence state, or
  child links directly

#### Scenario: Orchestration command spans domains

- **WHEN** an API command creates a packet, starts a work run, records an
  observation, accepts evidence, or records verification across multiple
  bounded contexts
- **THEN** the transport code MUST stay thin, build or receive session and
  operation context, call public context actions, and avoid owning lifecycle,
  authorization, validation, or evidence-acceptance rules

### Requirement: Packet Run Verification APIs Have Parity

Office Graph SHALL test equivalent GraphQL and JSON API behavior for the first
packet-run-verification flow.

#### Scenario: GraphQL and JSON API execute the flow

- **WHEN** both API surfaces create a packet, start a work run, record an
  observation, accept evidence, and read the summary projection
- **THEN** both surfaces MUST produce equivalent durable state, authorization
  decisions, operation correlation, validation errors, verification results,
  and response semantics

#### Scenario: API request is invalid

- **WHEN** either API surface receives invalid packet, run, observation,
  evidence, authorization, lifecycle, scope, or idempotency input
- **THEN** it MUST return a structured error with a stable code and safe
  explanatory detail equivalent to the other API surface

#### Scenario: Composite flow input is invalid

- **WHEN** a packet-run-verification orchestration request contains packet
  readiness input or passed-evidence input that the owning domain rules would
  later reject
- **THEN** the shared API context MUST reject the request before creating
  per-step operation-correlated packet, run, observation, candidate, evidence,
  or verification result records

#### Scenario: Composite observation source replay conflicts

- **WHEN** a packet-run-verification orchestration request reuses an observation
  source identity and idempotency key that already belongs to a different flow
  step, work run, check, status, freshness, trust basis, or graph linkage,
  including concurrent requests racing on the same absent observation key
- **THEN** the shared API context MUST reject the request as an idempotency
  conflict before creating packet, run, evidence, or verification-result records
  and MUST allow a corrected retry with the same flow identity when no durable
  flow step has been consumed

#### Scenario: Composite evidence result is unsupported

- **WHEN** a packet-run-verification orchestration request supplies an evidence
  result outside the supported acceptance vocabulary
- **THEN** the shared API context MUST reject the request before creating
  per-step operation-correlated packet, run, observation, candidate, evidence, or
  verification-result records

#### Scenario: Composite flow identity is reused with different input

- **WHEN** a packet-run-verification orchestration request reuses a flow
  identity with a different verification check, source graph item, packet
  contract, observation, evidence, or acceptance input
- **THEN** the shared API context MUST reject the request as an idempotency
  conflict instead of replaying prior durable packet, run, observation,
  candidate, evidence, verification result, or summary records

#### Scenario: Work packet operation replay conflicts

- **WHEN** a work-packet create operation is replayed with a different title,
  lifecycle-driving packet fields, source graph items, or verification checks
- **THEN** the work-packet domain MUST reject the replay as an operation
  conflict instead of returning a packet version recorded for a different
  packet contract

#### Scenario: Work run start operation replay conflicts

- **WHEN** a work-run start operation is replayed with a different packet
  version, authority posture, source surface, or reason
- **THEN** the runs domain MUST reject the replay as an operation conflict
  instead of returning a run started for a different packet contract or start
  intent

#### Scenario: Evidence candidate operation replay conflicts

- **WHEN** an evidence-candidate create operation is replayed with a different
  run, check, observation, artifact, source, claim, freshness, trust, or
  sensitivity input
- **THEN** the verification domain MUST reject the replay as an operation
  conflict instead of returning a candidate recorded for different evidence
  facts

#### Scenario: Evidence acceptance operation replay conflicts

- **WHEN** an evidence-acceptance operation is replayed for the same candidate
  with different result, policy basis, title, body, reason, or visibility input
- **THEN** the verification domain MUST reject the replay as an operation
  conflict instead of returning accepted evidence and verification results
  recorded for different acceptance facts
