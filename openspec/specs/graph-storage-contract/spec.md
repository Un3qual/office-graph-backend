# graph-storage-contract Specification

## Purpose
TBD - created by archiving change design-persistence-model. Update Purpose after archive.
## Requirements
### Requirement: Graph Identity With Typed Resources
Office Graph SHALL use shared graph identity for addressability while keeping
business meaning in typed resources.

#### Scenario: Addressable domain record is stored
- **WHEN** a signal, task, question, decision, check, evidence item, artifact,
  run, work packet, conversation, document section, or plan section becomes
  graph-addressable
- **THEN** it MUST have a graph identity record for traversal and projection
  and a typed resource record for fields, validations, lifecycle, and domain
  actions when the concept has business behavior

#### Scenario: Graph-addressable typed resource is created
- **WHEN** a domain action creates a graph-addressable typed resource
- **THEN** the graph identity record and typed resource record MUST be written
  in the same database transaction so either both become visible or neither
  becomes visible

#### Scenario: Graph identity allocation is requested
- **WHEN** a typed resource context needs graph addressability
- **THEN** it MUST use the graph identity context's public allocation contract
  while the typed resource context owns business validation and lifecycle

### Requirement: Typed Relationships
Office Graph SHALL persist graph edges as typed relationship records rather
than opaque edge payloads.

#### Scenario: Relationship is created
- **WHEN** two graph-addressable resources are linked for dependency,
  blocking, evidence, provenance, review, conversation, or verification
- **THEN** the relationship MUST store source, target, relationship type,
  organization scope, lifecycle state, provenance, and narrow typed metadata
  sufficient for authorization-filtered traversal

#### Scenario: Relationship needs substantive facts
- **WHEN** an edge would need to store an explanation, approval, finding,
  artifact, decision, evidence, or large payload
- **THEN** Office Graph MUST model that fact as a typed graph item, artifact,
  evidence record, or external reference linked by a typed relationship

### Requirement: No Polymorphic Local Resource References
Office Graph SHALL avoid polymorphic `type` plus `id` references for local
Office Graph resources in core persistence.

#### Scenario: Cross-domain local reference is needed
- **WHEN** a durable table needs to reference a first-class Office Graph
  resource across domain boundaries
- **THEN** it MUST use a concrete foreign key to graph identity or another
  concrete table, not a local `resource_type` plus `resource_id` pair

#### Scenario: Embedded domain reference is needed
- **WHEN** an embedded or high-volume structure needs to reference domain-owned
  records such as rich text blocks, gallery photos, table rows, or board cards
- **THEN** it MUST use a typed table with concrete foreign keys to those domain
  records rather than routing through a polymorphic local reference

#### Scenario: External provider identity is stored
- **WHEN** Office Graph stores an external provider object identifier
- **THEN** provider object type plus external identifier MAY be stored as
  external-reference identity because the target is outside the local SQL
  foreign-key model

### Requirement: API Interfaces Over Typed Storage
Office Graph SHALL implement GraphQL capability interfaces as API contracts
over concrete typed resources and authorization-aware domain contracts.

#### Scenario: Resource implements a capability interface
- **WHEN** a graph-addressable resource implements a GraphQL interface such as
  closable, updatable, reactable, comment-like, approvable, subscribable, or a
  future projection/configuration interface
- **THEN** its interface fields MUST be resolved from the resource's typed
  storage, graph identity, and owning domain contracts rather than from a
  polymorphic local `resource_type` plus `resource_id` table

#### Scenario: Viewer action field is exposed
- **WHEN** GraphQL exposes fields such as `viewerCanUpdate`,
  `viewerCanReact`, `viewerCanClose`, `viewerCanApprove`, or
  `viewerDidAuthor`
- **THEN** the resolver MUST use the authorization/policy boundary and current
  actor context instead of inferring permission from type membership alone

#### Scenario: Interface-backed mutation is proposed
- **WHEN** an API mutation would update, close, approve, react to, comment on,
  or otherwise mutate any interface implementor
- **THEN** the mutation MUST route through a typed domain action,
  proposed-graph-change path, or other explicit capability command that
  preserves validation, lifecycle, operation correlation, revision, audit, and
  authorization semantics

### Requirement: Scoped URL Identifiers Are Separate From Graph Identity
Office Graph SHALL keep optional scoped URL numbers or handles separate from
graph identity, GraphQL global IDs, and durable primary keys.

#### Scenario: Scoped URL number is allocated
- **WHEN** a future accepted design allocates a human-facing number such as a
  task, question, finding, view, workflow, pull request, or form number inside
  a scope
- **THEN** the allocation MUST store scope kind, scope identity, resource kind,
  number, allocation operation, and owning resource explicitly rather than
  deriving the URL number from a table primary key

#### Scenario: Scoped URL number is deleted or tombstoned
- **WHEN** a resource with a URL-facing scoped number is deleted, archived, or
  replaced
- **THEN** Office Graph MUST preserve a reservation or tombstone so the same
  scoped URL token is not reassigned to a different resource

#### Scenario: Allocation strategy is selected
- **WHEN** implementation chooses between Postgres sequences, per-scope
  sequence families, transactional counter rows, or another allocator
- **THEN** the design MUST state whether gaps are acceptable, how contention
  is handled, how retries behave, and how allocation participates in the same
  transaction as resource creation

### Requirement: Graph Projections Are Query Results
Office Graph SHALL treat graph projections as authorization-filtered query
results over scoped graph data, not as tenants or access-granting containers.

#### Scenario: Projection spans graph context
- **WHEN** a projection includes nodes, edges, artifacts, conversations,
  external references, revisions, summaries, or counts
- **THEN** every included record MUST remain governed by its own tenant, scope,
  sensitivity labels, and authorization facts

#### Scenario: Dedicated projection read model is proposed
- **WHEN** Office Graph introduces a persisted read model for inboxes, queues,
  node-neighborhood summaries, verification dashboards, agent-context caches,
  or another graph projection
- **THEN** the design MUST define the source truth tables, authorization and
  redaction rules, invalidation behavior, staleness contract, and operation
  correlation before the read model becomes durable MVP storage
