# ash-domain-boundaries Specification

## Purpose
Assign Ash resources and actions to explicit owning domains with enforceable cross-domain access.
## Requirements
### Requirement: Ash Domain Ownership
Each Ash domain and Ash resource SHALL belong to the bounded context that owns
the corresponding business lifecycle, validations, policies, and durable
records.

#### Scenario: A graph-addressable typed resource is added
- **WHEN** a typed resource participates in the work graph
- **THEN** the typed resource remains in its owning context and uses the graph
  context's public contract for graph identity and relationships

#### Scenario: A provider-neutral record is added
- **WHEN** a shared external concept such as a repository, pull request, check,
  review comment, or observability issue becomes first-class
- **THEN** its Ash resource is placed under the provider-neutral context that
  owns the concept rather than under a provider adapter

### Requirement: Public Ash Access
Cross-context callers and entrypoints MUST use exported domain commands,
queries, Ash actions, or read interfaces approved by the owning context.

#### Scenario: A resolver writes a resource
- **WHEN** a GraphQL resolver or JSON API handler performs a domain mutation
- **THEN** it calls the owning context's public command or approved Ash action
  rather than private resource internals

#### Scenario: A worker needs domain data
- **WHEN** an Oban worker, sync job, or agent task needs records from another
  context
- **THEN** it uses that context's exported query or read-model interface

### Requirement: Ash Policy Integration
Ash resources SHALL integrate with the authorization boundary for policy
decisions instead of duplicating authorization rules locally.

#### Scenario: A protected action is evaluated
- **WHEN** an Ash action requires authorization
- **THEN** the resource policy asks the authorization boundary for an
  explainable decision using actor, scope, classification, capability, and
  operation context

#### Scenario: A decision must be durable
- **WHEN** policy requires a denied, redacted, escalated, approval-gated, or
  sensitive-read decision to be durable
- **THEN** the Ash action path preserves the authorization decision reference
  for audit and operation correlation

### Requirement: Ash Mutation Side Effects
Ash changes, preparations, and notifiers MUST use shared contracts for
operation correlation, revisions, audit, domain events, tombstones, and raw
archives rather than writing another context's private tables directly.

#### Scenario: A task title is edited
- **WHEN** a mutable product record changes through an Ash action
- **THEN** the action path can record operation correlation and a typed
  revision through the approved shared contract

#### Scenario: A delete action is performed
- **WHEN** an Ash action soft-deletes a mutable product record
- **THEN** the action path uses the tombstone/soft-delete contract owned by the
  appropriate context and does not hard-delete normal product data

### Requirement: Transport Helpers Do Not Own Domain Behavior

Office Graph SHALL keep lifecycle, authorization, validation, operation
correlation, idempotency, audit, and revision behavior in owning domains rather
than transport-adjacent helper modules.

#### Scenario: API helper coordinates product state

- **WHEN** an API helper, resolver, controller, serializer, or frontend-facing
  adapter coordinates product state changes
- **THEN** it MUST delegate to an owning public domain command or approved Ash
  action and MUST NOT become the owner of transaction choreography or domain
  lifecycle rules

#### Scenario: Existing helper owns orchestration

- **WHEN** existing product behavior is found in a transport-adjacent helper
  such as an API support module
- **THEN** stabilization work MUST either move the behavior into an owning
  domain command or document the helper as a temporary compatibility exception
  with retirement criteria
- **AND WHEN** a helper is gated to local/dev/test request-owner bootstrap,
  including `OfficeGraph.ApiSupport.bootstrap_local_api_owner/0`
- **THEN** it is not a compatibility exception under this rule unless it begins
  owning product lifecycle, authorization, validation, idempotency, or audit
  behavior

### Requirement: Cross-Domain Workflows Prefer Durable Domain Commands

Office Graph SHALL decompose broad cross-domain workflow endpoints into durable
domain commands before treating the endpoint as a stable API endpoint.

#### Scenario: Packet, run, and verification workflow is decomposed

- **WHEN** the operator workflow is exposed through product transports
- **THEN** the implementation MUST split durable behavior into Ash-shaped
  commands owned by the relevant domains for packet preparation, run start,
  observation recording, evidence suggestion or acceptance, and verification
  recomputation, and MUST keep each transport command scoped to one durable step

#### Scenario: New cross-domain workflow is introduced

- **WHEN** a new workflow coordinates records across multiple bounded contexts
- **THEN** the proposal MUST first identify the smallest durable domain
  commands, their owners, allowed dependencies, transaction boundaries,
  idempotency basis, authorization contracts, and projection read contracts
  before introducing any one-shot orchestration endpoint

### Requirement: Domain Actions Own Lifecycle Transitions

Office Graph SHALL express stable lifecycle transitions through Ash actions or
public domain commands instead of scattered internal update helpers.

#### Scenario: Lifecycle state changes

- **WHEN** a task, review finding, verification check, work packet, run,
  required check, evidence item, evidence candidate, or verification state
  changes
- **THEN** the transition MUST pass through an owning Ash action or public
  command that validates allowed state, actor authority, scope, operation
  context, and audit/revision side effects

#### Scenario: Lifecycle write requires private action

- **WHEN** a lifecycle transition must remain private to a composite command
- **THEN** the private Ash action MUST be invoked only by the owning domain
  boundary and MUST not be exposed directly through generated API endpoints

### Requirement: Domain Read Contracts Are Projection-Aware

Office Graph SHALL separate plain resource reads from policy-filtered
projection reads.

#### Scenario: Mixed projection is needed

- **WHEN** a caller needs mixed workflow state such as inbox rows, packet
  readiness, run state, evidence state, or verification outcome
- **THEN** the caller MUST use a projection contract owned by the relevant
  domain or projection boundary rather than assembling semantics from raw Ash
  reads in a transport or frontend layer
