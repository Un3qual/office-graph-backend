# ash-api-surface Specification

## Purpose

Define the rules for GraphQL and JSON APIs over Ash-owned Office Graph
resources and actions.
## Requirements
### Requirement: Ash API Packages Are The Default

Office Graph SHALL expose Ash-owned resources and actions through AshGraphql
and AshJsonApi by default rather than hand-rolled GraphQL object trees or
Phoenix JSON controllers.

#### Scenario: Ash resource is exposed through GraphQL or JSON API

- **WHEN** an Ash resource, Ash action, or Ash domain-owned query becomes part
  of a product API
- **THEN** the implementation plan MUST first use AshGraphql and AshJsonApi
  declarations on the owning domain/resource or document why that path is a
  valid custom API exception

#### Scenario: Generated API package is mounted

- **WHEN** AshGraphql or AshJsonApi is mounted for a current resource-shaped
  read
- **THEN** tests MUST exercise the generated GraphQL field or generated
  `/api/v1` route; a mounted library without exercised generated reads is not
  enough evidence that the API uses Ash

#### Scenario: Resource API shape needs transport-specific presentation

- **WHEN** GraphQL or JSON API needs field naming, pagination, filtering,
  sorting, error presentation, or relationship shape that differs by transport
- **THEN** the transport layer MAY add mapping code, but the underlying action,
  authorization, validation, operation correlation, revision, audit, and
  lifecycle behavior MUST remain owned by the Ash resource/domain or public
  context contract

### Requirement: Old Manual API Code Must Stay Temporary

Office Graph SHALL treat the existing hand-written walking-skeleton GraphQL and
JSON transport code as temporary smoke-test code that must not spread to new
product APIs.

#### Scenario: New API work touches walking-skeleton endpoints

- **WHEN** future API work extends manual intake, change proposal application,
  verification completion, or walking-skeleton read behavior
- **THEN** the work MUST either migrate the path to AshGraphql/AshJsonApi or
  document the current caller, verification need, or data-safety reason that
  still requires the manual code

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
multi-step commands, mixed-data reads, or transport-specific response shapes
that do not map cleanly to generated Ash APIs.

#### Scenario: Custom transport code is kept

- **WHEN** custom GraphQL or Phoenix code remains after a generated Ash API is
  available
- **THEN** the custom code MUST be limited to mixed reads or commands that
  generated Ash APIs cannot express safely

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

#### Scenario: Domain adds GraphQL API

- **WHEN** a bounded context adds GraphQL types, fields, mutations,
  subscriptions, interfaces, or unions
- **THEN** schema ownership MUST live with the owning context, Ash resource, or
  API capability module, and the root schema MUST compose those modules rather
  than accumulating all definitions inline

#### Scenario: Capability interface is exposed

- **WHEN** GraphQL exposes shared interfaces such as closable, updatable,
  approvable, subscribable, readable through projection reads, comment-like, or reactable
  behavior
- **THEN** the interface implementation MUST use typed resource/domain
  contracts and viewer action fields rather than generic
  mutation paths or table-type switches

### Requirement: JSON API Uses AshJsonApi For Resource Endpoints

Office Graph SHALL use AshJsonApi for JSON API resource paths unless a
documented integration or workflow requirement needs a custom command endpoint.

#### Scenario: Client reads or mutates a resource collection

- **WHEN** JSON API exposes resource reads, resource relationships, create,
  update, delete, filtering, sorting, or pagination for Ash-owned data
- **THEN** the path MUST be planned as AshJsonApi-backed unless accepted
  design documents a custom exception

#### Scenario: Integration-friendly command endpoint is required

- **WHEN** an external integration, webhook-style flow, export, or workflow
  command needs a JSON endpoint that is not a natural resource action
- **THEN** the custom Phoenix endpoint MUST stay thin and call the same public
  context/domain command that GraphQL, jobs, agents, and other entrypoints use

### Requirement: Packet Run Verification Slice Uses Shared Domain APIs

Office Graph SHALL expose the first packet-run-verification slice through
shared domain actions and Ash-owned APIs.

#### Scenario: Resource API is exposed

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

### Requirement: Packet Run Verification Uses A GraphQL Command

Office Graph SHALL expose the first packet-run-verification flow through the
current GraphQL command and domain tests, not a duplicate hand-written JSON
route.

#### Scenario: GraphQL executes the current flow

- **WHEN** GraphQL creates a packet, starts a work run, records an observation,
  accepts evidence, and reads the summary data
- **THEN** the mutation MUST call `OfficeGraph.PacketRunVerification.execute/2`
  and return operation correlation, validation errors, structured authorization
  error or conflict outcomes, verification results, data changes, and safe
  response semantics

#### Scenario: API request is invalid

- **WHEN** the GraphQL command receives invalid packet, run, observation,
  evidence, authorization, lifecycle, scope, or idempotency input
- **THEN** it MUST return a structured error with a stable code and safe
  explanatory detail

#### Scenario: Old JSON command has no current caller

- **WHEN** no current non-test caller or accepted integration contract uses
  `/api/packet-run-verification/execute`
- **THEN** the Phoenix JSON route, controller, serializer, and route-level tests
  MUST be removed instead of kept as a fallback for `/operator`

#### Scenario: Composite flow input is invalid

- **WHEN** a packet-run-verification command contains packet readiness input or
  passed-evidence input that the owning domain rules would later reject
- **THEN** the GraphQL command MUST reject the request before creating
  per-step operation-correlated packet, run, observation, candidate, evidence,
  or verification result records

#### Scenario: Composite observation source replay conflicts

- **WHEN** a packet-run-verification command reuses an observation source
  identity and idempotency key that already belongs to a different flow step,
  work run, check, status, freshness, trust basis, or graph linkage, including
  concurrent requests racing on the same absent observation key
- **THEN** the shared API context MUST reject the request as an idempotency
  conflict before creating packet, run, evidence, or verification-result records
  and MUST allow a corrected retry with the same flow identity when no durable
  flow step has been consumed

#### Scenario: Composite evidence result is unsupported

- **WHEN** a packet-run-verification command supplies an evidence result outside
  the supported acceptance vocabulary
- **THEN** the shared API context MUST reject the request before creating
  per-step operation-correlated packet, run, observation, candidate, evidence, or
  verification-result records

#### Scenario: Composite flow identity is reused with different input

- **WHEN** a packet-run-verification command reuses a flow identity with a
  different verification check, source graph item, packet contract,
  observation, evidence, or acceptance input
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
  version, authority posture, source API, or reason
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

### Requirement: Manual API Migration Ledger

Office Graph SHALL keep a replacement ledger for hand-written GraphQL and JSON
API paths that remain during Ash API migration.

#### Scenario: Manual API path remains live

- **WHEN** a manual Absinthe root field, Phoenix JSON route, serializer, or
  transport-specific resolver remains live after stabilization begins
- **THEN** the implementation MUST document the owning capability, current
  caller or verification need, reason it cannot yet be generated through
  AshGraphql or AshJsonApi, replacement target, safety tests, and deletion
  condition

#### Scenario: New manual API path is proposed

- **WHEN** a change proposes new custom GraphQL or JSON API behavior
- **THEN** the design MUST classify it as a command exception, mixed-data read
  exception, integration/webhook exception, or named current need and MUST prove
  why generated Ash API declarations are not the default path

### Requirement: API Modules Are Transport-Separated By Capability

Office Graph SHALL keep GraphQL and JSON API code in separate transport
namespaces under the Phoenix web boundary.

#### Scenario: Manual API code is modularized

- **WHEN** manual GraphQL or JSON API compatibility code is split out of the
  current walking-skeleton files
- **THEN** GraphQL modules MUST live under `OfficeGraphWeb.GraphQL.*` and
  `lib/office_graph_web/graphql/`, JSON API modules MUST live under
  `OfficeGraphWeb.JsonApi.*` and `lib/office_graph_web/json_api/`, and modules
  MUST NOT mix Absinthe schema/resolver code with JSON API controller or
  serializer code

#### Scenario: API capability module is added

- **WHEN** a new GraphQL or JSON API module is added
- **THEN** it MUST be organized transport first, capability second, and purpose
  third; capability folders MAY represent bounded domains or custom command/read
  paths, while purpose files such as `types`, `queries`,
  `mutations`, `resolvers`, `controller`, and `serializer` MUST stay inside the
  relevant capability folder

#### Scenario: API helper is shared

- **WHEN** API behavior is shared by more than one endpoint or field
- **THEN** transport-specific helpers MUST live under that transport's `common`
  namespace, while domain behavior, command ownership, and projection contracts
  MUST live under `OfficeGraph.*` rather than a generic shared
  `OfficeGraphWeb.Api` namespace

### Requirement: Generated Ash Resource Reads Come First

Office Graph SHALL introduce generated AshGraphql and AshJsonApi resource
APIs for safe reads before exposing generated lifecycle writes.

#### Scenario: Product frontend reads Office Graph data

- **WHEN** the React product frontend reads resource-shaped or projection data
- **THEN** it MUST use GraphQL as the normal product API, while REST/JSON API
  remains a customer integration API and not the preferred internal UI
  transport

#### Scenario: JSON API resource reads are mounted

- **WHEN** generated AshJsonApi resource reads are exposed during stabilization
- **THEN** they MUST mount under `/api/v1`

#### Scenario: Resource read is migrated

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

### Requirement: Custom Commands Stay Thin

Office Graph SHALL keep custom API command and mixed-data read code thin when
generated Ash APIs do not fit.

#### Scenario: Command spans multiple bounded contexts

- **WHEN** a GraphQL mutation or JSON endpoint coordinates packets, runs,
  observations, evidence, verification, operations, authorization, or audit
- **THEN** the transport code MUST load context, call an owning public domain
  command, map transport-specific errors, and MUST NOT own lifecycle,
  authorization, idempotency, validation, or audit behavior

#### Scenario: Read spans multiple resource types

- **WHEN** a GraphQL field or JSON endpoint returns a policy-filtered mixed
  result
- **THEN** the transport code MUST call the owning read function and MUST
  NOT infer business semantics from raw resource type strings or private table
  structure

### Requirement: API Migration Preserves Safety Behavior

Office Graph SHALL preserve safety-critical behavior while replacing manual API
paths with generated Ash APIs or custom command exceptions.

#### Scenario: Replacement API is introduced

- **WHEN** a generated Ash API or new custom command/read path replaces a manual
  endpoint
- **THEN** tests MUST prove equivalent authorization behavior, operation
  context, validation errors, idempotency semantics, data changes, and safe
  structured errors for every current API path, without preserving old response
  envelopes or field names unless a named external contract requires them
