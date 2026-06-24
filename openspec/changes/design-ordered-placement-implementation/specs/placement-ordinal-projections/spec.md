## ADDED Requirements

### Requirement: Dense Ordinals Are Derived State
Office Graph SHALL derive dense ordinals, display indexes, slide numbers,
card positions, and list numbers from durable placement order instead of
treating them as source-of-truth write values.

#### Scenario: Ordered list is displayed
- **WHEN** a UI, API, agent context package, export, or projection displays an
  ordered collection
- **THEN** Office Graph MUST derive display ordinals from current active
  placement order and MUST preserve placement identity separately from the
  visible ordinal

#### Scenario: Command attempts to write by dense ordinal
- **WHEN** a reorder command is expressed only as a dense ordinal or display
  row number
- **THEN** Office Graph MUST translate the request into relative placement
  intent against an authorized current result or reject it as ambiguous

### Requirement: Ordered Projections Are Authorization Filtered
Office Graph SHALL apply authorization, scope, lifecycle, sensitivity, and
tombstone filters before exposing ordered projection results.

#### Scenario: Projection contains restricted siblings
- **WHEN** an ordered collection contains siblings that the actor cannot view
  directly
- **THEN** Office Graph MUST hide the siblings, show policy-approved
  placeholders, or show policy-approved summaries without leaking restricted
  item content or unauthorized absolute positions

#### Scenario: Visible ordinals are computed
- **WHEN** policy does not permit disclosing hidden sibling counts or absolute
  positions
- **THEN** Office Graph MUST compute visible dense ordinals relative to the
  authorized result set rather than the full unfiltered collection

### Requirement: Ordered Pagination Uses Stable Placement Cursors
Office Graph SHALL paginate ordered collections with placement-aware cursors or
source watermarks instead of durable dense ordinal offsets.

#### Scenario: Ordered page is requested
- **WHEN** a client requests the next or previous page of an ordered
  collection
- **THEN** the page cursor MUST be based on stable placement order state,
  projection filters, and source watermark rather than a mutable display
  ordinal alone

#### Scenario: Collection changes during pagination
- **WHEN** placements are inserted, moved, deleted, restored, or rebalanced
  while a client is paging through a collection
- **THEN** Office Graph MUST either preserve cursor semantics for the requested
  snapshot or return a stale/refetch signal defined by the projection contract

### Requirement: Persisted Ordered Read Models Are Rebuildable
Office Graph SHALL treat persisted ordered projections and ordinal caches as
derived state that can be invalidated and rebuilt from placement truth.

#### Scenario: Ordered read model is introduced
- **WHEN** a high-traffic surface introduces a persisted ordered projection,
  ordinal cache, board view, or agent-context ordered read model
- **THEN** the design MUST identify source placement records, source operation
  watermark, authorization inputs, sensitivity inputs, invalidation events,
  staleness behavior, and rebuild path

#### Scenario: Placement operation changes source order
- **WHEN** insertion, move, delete, restore, rebalance, or repair changes
  current placement state
- **THEN** Office Graph MUST invalidate, update, or mark stale every affected
  ordered read model according to its projection contract

### Requirement: Realtime Ordering Events Are Projection Hints
Office Graph SHALL use realtime ordering events as projection reconciliation
hints rather than as authoritative replacements for durable reads.

#### Scenario: Client receives ordering update
- **WHEN** a realtime event announces that a placement was inserted, moved,
  deleted, restored, rebalanced, or repaired
- **THEN** the event MUST include enough placement identity, collection
  identity, operation identity, and source watermark for the projection client
  to patch safely or refetch
