# shared-operation-contracts Specification

## Purpose
Define operation-context propagation across domain commands, workers, integrations, and agents.
## Requirements
### Requirement: Operation Context Propagation
Meaningful durable actions SHALL receive or create an operation context,
including writes, external syncs, agent actions, approvals, denials, revisions,
audit events, run events, domain events, tombstones, raw archive links, and
change proposals.

The canonical durable field list for operation correlation is owned by
`design-revision-audit-soft-delete/specs/operation-correlation`. Code
organization owns how entrypoints and contexts propagate that operation
context through public APIs.

Operation correlation starts as `OfficeGraph.Operations`, a dedicated context
for operation context structs, idempotency basis, and durable operation
records.

#### Scenario: A human submits a command
- **WHEN** an API request performs a durable write
- **THEN** the entrypoint builds an operation context with organization, scope,
  actor, command key, request/trace identifiers, authority basis, and source
  before calling domain code

#### Scenario: An agent performs an action
- **WHEN** an agent runtime tool performs a durable write or external action
- **THEN** the operation context includes the agent run, delegator or authority
  basis, tool/integration scope, and autonomy-policy context when applicable

### Requirement: Concern Separation
Historical and trace records MUST remain separate typed record families linked
by operation correlation where appropriate, including revisions, audit records,
authorization decisions, domain events, run events, external sync events, raw
archives, tombstones, and operation correlation records.

#### Scenario: A sensitive write changes product state
- **WHEN** one command changes product state and requires audit
- **THEN** it may create a typed revision, audit event, authorization decision,
  domain event, and operation record without using any one record family as a
  substitute for the others

#### Scenario: A raw provider payload is archived
- **WHEN** a webhook or provider API response is stored for replay or
  provenance
- **THEN** the raw archive stores the original payload and typed extracted
  product records store queryable domain fields separately

### Requirement: Concrete References
Shared operation contracts MUST use concrete local references, typed target
rows, or typed envelopes rather than polymorphic local `type` plus `id` links
for Office Graph-owned resources.

#### Scenario: An audit event references targets
- **WHEN** an audit event records affected resources
- **THEN** target rows use allowed concrete target references or typed target
  envelopes defined by the audit boundary

#### Scenario: An operation references a primary object
- **WHEN** an operation correlation record identifies its primary graph or
  domain object
- **THEN** it uses the approved graph identity or concrete domain reference
  instead of an unbounded local polymorphic reference

### Requirement: Shared Contract Ownership
Cross-context operation contracts SHALL be owned by explicit shared contexts or
library-ready primitives and SHALL expose stable functions, structs,
behaviours, or event APIs for callers.

#### Scenario: A new context needs revisions
- **WHEN** a product context introduces a mutable aggregate with revision
  requirements
- **THEN** it uses the approved revision contract instead of inventing an
  unrelated history table pattern

#### Scenario: A new context emits domain events
- **WHEN** a context emits events consumed by other contexts
- **THEN** it uses the approved domain-event contract and includes operation
  correlation when the event comes from a meaningful command

### Requirement: Transactional Side Effects
Durable domain actions SHALL keep truth-table mutations and side effects
transactionally safe.

#### Scenario: Durable domain action writes product state
- **WHEN** a domain action changes product state
- **THEN** it MUST write product state, operation correlation, revisions, and
  audit records in one approved transaction boundary where those records apply

#### Scenario: External side effect is needed
- **WHEN** a domain action needs a job, domain event, notification, export, or
  external write
- **THEN** it MUST enqueue or emit that side effect through an approved
  transaction-safe mechanism so retries cannot create duplicate truth-table
  mutations

### Requirement: Durable Delivery Preserves Operation And Causation

Office Graph SHALL correlate domain events and durable jobs with the operation
that requested them and with a causal event when one exists.

#### Scenario: Command records an event and job

- **WHEN** a meaningful operation commits product state that requires durable
  delivery
- **THEN** its event and job MUST reference that operation, use the same tenant
  scope, and commit or roll back atomically with the owning transaction

#### Scenario: Event causes later work

- **WHEN** a dispatched event requests another operation or durable job
- **THEN** the later record MUST preserve the causation event identity without
  merging separate operations or duplicating their data

### Requirement: System Operations Use A Separate Authenticated Envelope
Office Graph SHALL create non-human system operations from a request that names
organization, service or webhook principal, authority basis, action, causation,
idempotency scope, optional governing workspace, optional subject/version, and
credential reference when required.

#### Scenario: Webhook source starts an operation
- **WHEN** a verified active installation webhook starts supported processing
- **THEN** Office Graph MUST create or replay a system operation bound to the
  installation source principal and organization without fabricating a session

#### Scenario: Unsupported system action is requested
- **WHEN** a service principal requests an action outside its capabilities,
  installation scope, or declared job kinds
- **THEN** Office Graph MUST deny it before operation or job creation

### Requirement: Human And System Operation Invariants Remain Distinct
Office Graph SHALL prevent system-operation optional fields from weakening
human operation validation.

#### Scenario: Human mutation starts an operation
- **WHEN** GraphQL or JSON API handles a human product command
- **THEN** it MUST continue to require the authenticated principal, session,
  organization, workspace, and command-specific subject data

#### Scenario: Worker receives malformed system operation
- **WHEN** a worker receives missing authority basis, principal, organization, or
  idempotency scope
- **THEN** it MUST fail closed with a safe terminal classification
