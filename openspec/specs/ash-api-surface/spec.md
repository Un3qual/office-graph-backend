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

#### Scenario: Generated API declaration names a field or route

- **WHEN** an Ash domain or resource declares generated GraphQL fields,
  GraphQL types, JSON API routes, or JSON API types
- **THEN** the declaration MUST stay declarative and MUST NOT reference
  `OfficeGraphWeb`, Plug/Phoenix request or response modules, Absinthe
  resolver modules, request session loading, transport serializers, or
  response-envelope mapping

#### Scenario: Generated API declaration needs transport behavior

- **WHEN** a generated AshGraphql or AshJsonApi declaration needs request
  context loading, response shaping, workflow orchestration, mixed-resource
  projection assembly, or transport-specific error mapping
- **THEN** the behavior MUST move to the appropriate `OfficeGraphWeb.GraphQL.*`
  or `OfficeGraphWeb.JsonApi.*` module as custom transport code backed by a
  public domain, command, or projection contract

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

#### Scenario: Product GraphQL object has stable identity

- **WHEN** a product GraphQL object represents a stable resource or projection
  object
- **THEN** it MUST implement Relay Node identity with an opaque `id`, while raw
  resource identifiers MUST be exposed only through explicitly named fields
  needed for command inputs, audit traces, or compatibility during migration

#### Scenario: Product GraphQL operation returns a growing list

- **WHEN** a product GraphQL read returns a list that can grow beyond one
  screenful or one command response
- **THEN** it MUST use Relay connection shape with `edges`, per-edge cursors,
  and `pageInfo`, using the Absinthe Relay server package rather than a
  route-specific pagination object

#### Scenario: Product UI asks for JSON API compatibility

- **WHEN** a product UI route can read or command workflow state through the
  product GraphQL path
- **THEN** the frontend MUST NOT add or keep a JSON API adapter for that route
  unless an accepted OpenSpec change names a current external contract,
  migration need, or data-safety reason and a retirement condition

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

### Requirement: Packet And Verification Commands Use Shared Domain APIs

Office Graph SHALL expose packet, run, observation, evidence, and verification
behavior through shared domain actions and Ash-owned APIs.

#### Scenario: Resource API is exposed

- **WHEN** packet versions, work runs, execution observations, evidence
  candidates, accepted evidence, or verification results are exposed for API
  reads or simple resource mutations
- **THEN** the implementation MUST use AshGraphql and AshJsonApi declarations
  on the owning domain/resource or document a narrow custom transport
  exception

#### Scenario: Domain-owned command creates are not exposed as simple resource creates

- **WHEN** packet creation, packet-version readiness, packet source links,
  packet required-check links, work-run lifecycle, run required checks,
  execution observations, evidence candidates, or accepted evidence require
  command-owned derivation, operation validation, idempotency,
  evidence-acceptance rules, or packet-contract checks
- **THEN** Office Graph MUST keep those create actions private to the owning
  domain command and MUST not expose generated public resource creates that let
  callers choose lifecycle state, candidate state, accepted-evidence state, or
  child links directly

#### Scenario: Product command advances one owned step

- **WHEN** an API command creates a packet, starts a work run, records an
  observation, creates or accepts evidence, or records a verification decision
- **THEN** the transport code MUST stay thin, resolve session and operation
  context, call exactly one owning domain command, and avoid owning lifecycle,
  authorization, validation, or evidence-acceptance rules

### Requirement: Operator Workflow Uses Step-Specific Commands

Office Graph SHALL expose the operator workflow through separate GraphQL and
JSON commands for packet creation, run start, observation recording, evidence
candidate creation, evidence acceptance, and verification waiver.

#### Scenario: API client executes the current flow

- **WHEN** a client creates a packet, starts a work run, records an observation,
  creates and accepts evidence, and reads the resulting projections
- **THEN** each command MUST call its owning domain action and return operation
  correlation, affected identities, structured authorization, validation, and
  conflict outcomes, and safe response semantics

#### Scenario: API request is invalid

- **WHEN** a step-specific command receives invalid packet, run, observation,
  evidence, authorization, lifecycle, scope, or idempotency input
- **THEN** it MUST return a structured error with a stable code and safe
  explanatory detail

#### Scenario: Equivalent API families execute a command

- **WHEN** GraphQL and JSON clients execute the same operator command
- **THEN** both API families MUST preserve the same domain authorization,
  validation, idempotency, conflict, audit, and result semantics even when
  their transport envelopes differ

#### Scenario: Workflow commands remain independently retryable

- **WHEN** a command is retried with the same operation identity and equivalent
  normalized input
- **THEN** it MUST return its original durable result, while changed input MUST
  return a stable idempotency conflict without mutating completed steps

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

### Requirement: Generated Ash API migration has a terminal state

Office Graph SHALL complete the AshGraphql and AshJsonApi migration without a
shared manual compatibility API layer.

#### Scenario: Resource-shaped API path exists

- **WHEN** GraphQL or JSON API reads or mutates an Ash-owned resource,
  relationship, calculation, aggregate, or action
- **THEN** the owning domain MUST expose it through AshGraphql or AshJsonApi
  unless the accepted custom-path inventory proves the pinned package cannot
  express the required behavior safely

#### Scenario: Generated migration completes

- **WHEN** the final generated API replacement is verified
- **THEN** `OfficeGraphWeb.OperatorCommands`, GraphQL or JSON API
  `operator_commands` folders, duplicate resource object definitions, and
  compatibility aliases MUST NOT remain

#### Scenario: Manual API path remains

- **WHEN** a hand-written Absinthe field or Phoenix JSON route remains after
  migration
- **THEN** it MUST be a named mixed-projection, webhook, or provider-callback
  exception with an owning capability, public domain or projection contract,
  safety tests, and evidence that generated Ash APIs are insufficient

### Requirement: Ash owns resource Relay behavior

AshGraphql SHALL own global ID encoding, generated resource object types,
resource node loading, and connection pagination for Ash-backed GraphQL reads.

#### Scenario: Stable Ash resource is exposed

- **WHEN** a stable Ash resource record is returned by GraphQL
- **THEN** its generated object MUST implement Relay Node with an opaque global
  `id` and authorized refetch through its owning Ash read action

#### Scenario: Growing Ash resource list is exposed

- **WHEN** a generated GraphQL list can grow beyond one bounded response
- **THEN** its owning read action and GraphQL declaration MUST use
  keyset-backed Relay connection pagination

#### Scenario: Relay ID is accepted by an action

- **WHEN** a generated action argument identifies another GraphQL resource
- **THEN** the declaration MUST use `relay_id_translations` and MUST reject
  malformed, raw, cross-type, missing, or unauthorized identifiers safely

#### Scenario: Stable mixed projection is exposed

- **WHEN** a stable mixed-resource projection cannot be represented safely as
  an Ash resource read
- **THEN** it MAY use an Absinthe Relay `node object` only if it has opaque
  identity, authorized refetch, an accepted custom-path entry, and no duplicate
  Ash resource object

#### Scenario: Nested projection value has no independent identity

- **WHEN** a nested value exists only within one projection response and has no
  independent lifecycle or refetch contract
- **THEN** it MUST remain an ordinary typed object rather than receive an
  invented Relay Node identity

### Requirement: Commands are generated from owning Ash actions

Commands exposed through both GraphQL and JSON API SHALL use one typed generic
or resource action on the command's owning Ash resource.

#### Scenario: Step-specific command is exposed

- **WHEN** GraphQL or JSON API exposes a current step-specific product command
- **THEN** the owning Ash action MUST define its public arguments and
  validation, receive the authenticated actor, call the existing public domain
  command, and return an Ash resource, action metadata, or an explicitly typed
  result

#### Scenario: Both transports expose a command

- **WHEN** a command is available through GraphQL and JSON API
- **THEN** AshGraphql and AshJsonApi MUST expose the same owning Ash action
  rather than separate resolver and controller implementations

#### Scenario: Command returns a resource

- **WHEN** a command result is an Ash resource record
- **THEN** GraphQL and JSON API MUST use the generated resource type instead of
  a hand-written command-result object with duplicate fields

#### Scenario: Command returns multiple values

- **WHEN** a command genuinely returns multiple independent records or
  operation facts
- **THEN** it MUST use action metadata or a responsibility-owned typed result
  struct and MUST NOT return an untyped map or transport-owned DTO

### Requirement: Generated APIs use typed Ash errors

Office Graph SHALL represent safe command failures as typed Ash errors that
both generated API packages can serialize.

#### Scenario: Domain command returns a stable failure

- **WHEN** a generated action encounters authorization, validation, not-found,
  idempotency, lifecycle, or concurrency failure
- **THEN** it MUST return a typed Ash error with safe code, field or path when
  applicable, and non-sensitive detail

#### Scenario: GraphQL serializes a domain error

- **WHEN** AshGraphql returns a typed command failure
- **THEN** the error MUST be converted through `AshGraphql.Error` and any
  owning-domain error handler without a central web-layer switch over all
  commands

#### Scenario: JSON API serializes a domain error

- **WHEN** AshJsonApi returns the same typed command failure
- **THEN** the error MUST be converted through `AshJsonApi.ToJsonApiError` and
  any owning-domain error handler with equivalent code and safe meaning

### Requirement: Relationship fields use declarative loading

GraphQL and JSON API relationship fields SHALL be generated from Ash
relationships, calculations, aggregates, or accepted typed projection actions.

#### Scenario: Ash relationship is exposed

- **WHEN** an API field returns records available through an Ash relationship
- **THEN** the generated field and package loader MUST be used instead of a
  hand-written resolver that fetches the related records

#### Scenario: Custom Absinthe dataloader is necessary

- **WHEN** an accepted custom projection field requires Absinthe Dataloader
  outside AshGraphql
- **THEN** the field MUST declare `resolve: dataloader(Source)` directly and
  MUST NOT add a block field or wrapper resolver that only delegates to the
  dataloader

#### Scenario: JSON API relationship is supported

- **WHEN** an external JSON API client needs a supported resource relationship
- **THEN** the owning AshJsonApi domain MUST expose a generated related or
  relationship route with the resource's authorization and lifecycle rules

#### Scenario: Signal graph spine is read

- **WHEN** an authorized client reads a Signal and follows its graph item,
  tasks, review findings, or verification checks
- **THEN** AshGraphql MUST return generated Relay resource nodes and
  connections, and AshJsonApi MUST expose the corresponding generated resource
  and related routes

#### Scenario: Graph relationship endpoints require redaction

- **WHEN** a client traverses relationships whose opposite endpoint may not be
  authorized
- **THEN** the generated GraphItem read MUST remain the resource identity
  surface while the classified redacted relationship-view projection filters
  or redacts endpoints without exposing the underlying GraphRelationship
  resource as an unrestricted generated read

#### Scenario: Run conversation resources are read

- **WHEN** an authorized client reads a run conversation, its messages, agent
  executions, approval requests, or context-expansion requests
- **THEN** AshGraphql MUST return generated Relay resource nodes and
  connections, AshJsonApi MUST expose generated resource and related routes,
  and the mixed operator projection MUST retain only command affordances,
  source watermarking, and independently redacted message-context facts

### Requirement: Manual API Migration Ledger

Office Graph SHALL replace the temporary manual migration ledger with a
terminal custom-path inventory containing only accepted mixed-projection,
webhook, and provider-callback exceptions.

#### Scenario: Manual API path remains live

- **WHEN** a manual Absinthe root field, Phoenix JSON route, serializer, or
  transport-specific resolver remains after this migration
- **THEN** the implementation MUST record its owning capability, exception
  class, reason the pinned AshGraphql or AshJsonApi package is insufficient,
  public domain or projection contract, safety tests, and retirement condition
  when the limitation is temporary

#### Scenario: New manual API path is proposed

- **WHEN** a later change proposes new custom GraphQL or JSON API behavior
- **THEN** the accepted design MUST classify it as a mixed-projection, webhook,
  or provider-callback exception and MUST prove why generated Ash API
  declarations are insufficient

#### Scenario: Compatibility path has no terminal exception

- **WHEN** a manual resolver, controller, serializer, input parser, error
  classifier, object definition, field alias, or route exists only to preserve
  the pre-release API migration shape
- **THEN** canonical verification MUST reject it and require deletion

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
surfaces for safe reads before exposing generated lifecycle writes.

#### Scenario: Product frontend reads Office Graph data

- **WHEN** the React product frontend reads resource-shaped or projection data
- **THEN** it MUST use GraphQL as the normal product API, while REST/JSON API
  remains a customer integration surface and not the preferred internal UI
  transport

#### Scenario: Generated GraphQL read is exposed

- **WHEN** a generated AshGraphql read is exposed for product frontend use
- **THEN** stable resource objects MUST expose opaque Relay Node `id` values
  and growing generated list reads MUST use Relay connection shape rather than
  raw arrays

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

### Requirement: Product Write APIs Use Step-Specific Commands

Office Graph SHALL expose product writes as thin GraphQL and JSON transport
modules over named domain commands and operation correlation.

#### Scenario: Product command is exposed

- **WHEN** a transport exposes manual intake, proposal apply, packet create or
  version, run start, observation, evidence, or waiver behavior
- **THEN** the transport MUST resolve the request session, parse transport
  input, start the named operation, call one owning domain command, and map its
  result or safe error without reimplementing domain workflow logic

#### Scenario: API families expose the command loop

- **WHEN** GraphQL and JSON API clients execute equivalent operator commands
- **THEN** both API families MUST enforce the same authorization, validation,
  idempotency, conflict, audit, and result semantics even when their transport
  envelopes differ

### Requirement: Unreleased One-Shot Workflow Mutation Is Removed

Office Graph SHALL remove the packet-run-verification one-shot transport after
step-specific commands replace its supported behavior.

#### Scenario: Replacement command sequence is verified

- **WHEN** API and product tests cover packet creation, run start, observation,
  evidence creation, and evidence acceptance as separate operations
- **THEN** the GraphQL schema MUST no longer expose
  `executePacketRunVerification`, and transport-only input and result modules
  with no current caller MUST be deleted
