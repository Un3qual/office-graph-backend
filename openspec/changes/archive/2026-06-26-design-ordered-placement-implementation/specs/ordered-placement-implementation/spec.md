## ADDED Requirements

### Requirement: Placement Scope Is Explicit
Office Graph SHALL model ordered placement as scoped collection membership
rather than as authorization, tenancy, or generic graph ownership.

#### Scenario: Ordered collection is created
- **WHEN** an ordered collection is created for a graph-addressable or typed
  domain surface
- **THEN** it MUST identify organization scope, applicable workspace,
  initiative or workstream scope, collection kind, structure kind, ordering
  strategy, lifecycle state, and one concrete owner reference

#### Scenario: Ordered collection is read
- **WHEN** a user, agent, integration, or system job reads an ordered
  collection
- **THEN** Office Graph MUST enforce each placed item's own authorization,
  lifecycle, sensitivity, tombstone, and typed resource rules before exposing
  the item in the ordered result

### Requirement: Placement Storage Uses Concrete References
Office Graph SHALL implement reusable placement behavior without polymorphic
local owner or item references.

#### Scenario: Graph-addressable placement storage is used
- **WHEN** a shared ordered placement table stores graph-addressable
  collection membership
- **THEN** it MUST use concrete graph identity foreign keys for the owner,
  item, collection, parent placement, and placement version relationships

#### Scenario: Typed domain placement storage is used
- **WHEN** rich text blocks, task-list entries, gallery photos, plan sections,
  or another typed domain requires embedded or high-volume ordering
- **THEN** the domain MUST use typed placement tables or fields with concrete
  domain foreign keys while preserving the shared placement contract

### Requirement: Generic Placement Storage Is Deferred
Office Graph SHALL defer generic ordered placement storage and broad shared
ordering APIs until a later accepted change selects a concrete product
surface.

#### Scenario: No generic ordering surface is selected
- **WHEN** current planning has not accepted a product surface that requires
  graph-addressable cross-domain ordered membership
- **THEN** Office Graph MUST NOT add generic placement tables, generic reorder
  APIs, ordering background jobs, persisted ordinal caches, or ordering
  migrations for that surface

#### Scenario: Generic ordering surface is selected later
- **WHEN** a later product surface is proposed for generic ordered placement
- **THEN** the proposal MUST identify the storage owner, typed domain command
  boundary, allowed callers, migration shape, uniqueness strategy, lifecycle
  model, projection contract, and operation/revision/audit traceability before
  implementation begins

### Requirement: Placement Commands Own Insertions And Moves
Office Graph SHALL route placement writes through domain-owned commands that
validate placement intent before writing durable order state.

#### Scenario: Item is inserted between siblings
- **WHEN** a command inserts an item into an ordered collection using before,
  after, parent, or append/prepend intent
- **THEN** the owning domain action MUST validate scope, authorization, item
  eligibility, sibling membership, lifecycle, and idempotency before creating
  placement state

#### Scenario: Item is moved without content changes
- **WHEN** a command moves an existing placement to a new sibling position or
  parent without changing the placed item's content
- **THEN** Office Graph MUST create placement version state for the move and
  MUST NOT create an unrelated content revision

### Requirement: Placement Lifecycle And Uniqueness Are Enforced
Office Graph SHALL enforce membership lifecycle, parent, and position
uniqueness at the placement boundary.

#### Scenario: Active placement is written
- **WHEN** an active placement is inserted, moved, restored, or rebalanced
- **THEN** active position-key uniqueness MUST be scoped by collection, parent
  placement, active lifecycle state, and position key using a root-safe parent
  scope for top-level siblings

#### Scenario: Duplicate active membership is proposed
- **WHEN** a command would create more than one active membership for the same
  item in a collection that does not explicitly allow duplicates
- **THEN** Office Graph MUST reject the command or route it through a domain
  action that first closes, supersedes, or restores the existing membership

#### Scenario: Nested placement is moved
- **WHEN** a placement is moved under a parent placement
- **THEN** Office Graph MUST reject cycles, cross-collection parent links,
  deleted parents, and parent relationships that violate the collection's
  structure kind

### Requirement: Placement Strategies Extend Additively
Office Graph SHALL add new ordering strategies without replacing the placement
identity, lifecycle, revision, and concrete-reference contract.

#### Scenario: New strategy is introduced
- **WHEN** grid placement, swimlanes, board columns, gallery-specific ordering,
  topological ordering, priority ranking, or another strategy is accepted
- **THEN** it MUST attach typed strategy data through additive tables or typed
  placement-version records while preserving collection identity, placement
  identity, item identity, operation correlation, and historical
  reconstruction
