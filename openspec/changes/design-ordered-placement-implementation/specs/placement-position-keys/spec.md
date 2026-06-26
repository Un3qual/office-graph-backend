## ADDED Requirements

### Requirement: Position Keys Are Opaque Sortable Values
Office Graph SHALL use opaque lexicographically sortable fractional position
keys as the first reusable manual ordering strategy.

#### Scenario: Position key is persisted
- **WHEN** a placement version stores a manual ordering position
- **THEN** the position key MUST use a fixed ASCII alphabet, bytewise sortable
  comparison semantics, a documented maximum length, and no dependency on
  floating-point precision

#### Scenario: API client reorders an item
- **WHEN** a client, agent, integration, or generated UI requests a reorder
- **THEN** it MUST express relative move intent or an opaque placement cursor
  rather than generating durable position keys itself

### Requirement: Position Keys Are Generated From Sibling Bounds
Office Graph SHALL generate position keys from the nearest active sibling
bounds under the same collection and parent.

#### Scenario: Item is inserted between two siblings
- **WHEN** a command inserts or moves a placement between two active sibling
  placements
- **THEN** Office Graph MUST generate a key that sorts after the previous
  sibling and before the next sibling within the same collection and parent

#### Scenario: Item is prepended or appended
- **WHEN** a command inserts at the start or end of an active sibling range
- **THEN** Office Graph MUST generate a key using the one available neighbor
  or the empty sibling range without renumbering unrelated parents

### Requirement: Placement Conflicts Preserve User Intent
Office Graph SHALL use optimistic placement and collection version checks so
concurrent reorders do not silently overwrite each other.

#### Scenario: Move preconditions still identify the same intent
- **WHEN** a placement command detects stale collection or placement versions
  but the referenced before, after, parent, and item placements still make the
  original intent unambiguous
- **THEN** the command MAY reload the latest sibling keys and retry under the
  same idempotency and authorization context

#### Scenario: Move intent is ambiguous after concurrent changes
- **WHEN** a stale reorder command references moved, deleted, restricted,
  lifecycle-changed, or cross-parent siblings such that the original intent is
  no longer clear
- **THEN** Office Graph MUST return a conflict or create a change proposal
  instead of applying a last-write-wins reorder

### Requirement: Rebalance Preserves Relative Order
Office Graph SHALL treat rebalancing as a placement operation that rewrites
position keys without changing item content or relative sibling order.

#### Scenario: Sibling key space is exhausted
- **WHEN** repeated inserts make a sibling range gap too small, position keys
  exceed the accepted length threshold, or concentrated edits make future
  insertion unsafe
- **THEN** Office Graph MUST rebalance the affected collection and parent
  sibling range by creating new placement version state under one operation
  correlation record

#### Scenario: Rebalance affects visible projection
- **WHEN** a rebalance changes position keys without changing relative order
- **THEN** Office Graph MUST preserve display order, avoid content revisions,
  and emit the invalidation or realtime signal needed for ordered projections
  to refresh their source watermark

### Requirement: Placement Repair Is Explicit And Explainable
Office Graph SHALL detect corrupt placement state and repair only when the
repair is deterministic and traceable.

#### Scenario: Repairable placement inconsistency is detected
- **WHEN** duplicate active keys, broken denormalized current fields, missing
  current versions, or orphaned parent references can be reconstructed from
  placement versions inside one organization and collection
- **THEN** Office Graph MAY repair the state through a placement repair
  operation that records operation correlation, affected placements, and
  projection invalidation

#### Scenario: Placement inconsistency is not safely repairable
- **WHEN** placement state cannot be reconstructed deterministically or spans
  policy boundaries that the repair actor cannot administer
- **THEN** Office Graph MUST mark the collection degraded, preserve evidence
  for investigation, and require an explicit administrator or support repair
  workflow before silent rewriting occurs
