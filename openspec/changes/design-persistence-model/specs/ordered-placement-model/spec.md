## ADDED Requirements

### Requirement: Ordered Placement Contract
Office Graph SHALL model reusable ordering semantics as an ordered-placement
contract that can be implemented by graph-addressable tables or typed embedded
tables.

#### Scenario: Ordered structure is persisted
- **WHEN** Office Graph persists an ordered list, plan section list, task list,
  board lane, document block list, gallery, slide list, or future ordered
  structure
- **THEN** the durable model MUST represent stable collection identity, stable
  item membership, parent placement where nesting is allowed, position key,
  lifecycle state, and revision or operation validity

### Requirement: No Polymorphic Placement Foreign Keys
Office Graph SHALL NOT use polymorphic local `owner_type`/`owner_id` or
`item_type`/`item_id` pairs as the durable ordering model.

#### Scenario: Generic ordered placement is proposed
- **WHEN** a generic ordered placement table is used for first-class
  graph-addressable resources
- **THEN** owner and item references MUST be concrete foreign keys to graph
  identity records rather than polymorphic local type/id pairs

#### Scenario: Embedded ordered placement is proposed
- **WHEN** ordered items are embedded, high-volume, or domain-specific
- **THEN** Office Graph MUST use a typed placement table with concrete foreign
  keys to the owner and item tables

### Requirement: Graph-Addressable Ordered Collections
Office Graph SHALL support generic ordered collections for first-class
graph-addressable resources through concrete graph identity foreign keys.

#### Scenario: Ordered graph resources are stored
- **WHEN** tasks, plan sections, graph-addressable document sections, cards,
  or other first-class resources need reusable ordering
- **THEN** the placement table MAY use `owner_graph_item_id` and
  `item_graph_item_id` foreign keys, collection kind, structure kind,
  ordering strategy, parent placement, position key, and lifecycle state

### Requirement: Typed Embedded Ordered Placements
Office Graph SHALL support typed placement tables for embedded or
domain-specific ordered structures.

#### Scenario: Rich text block order is stored
- **WHEN** rich text document blocks are ordered
- **THEN** Office Graph SHOULD use a typed rich text placement table with
  concrete document, block, parent placement, position key, and revision
  validity columns that follow the shared ordered-placement contract

#### Scenario: Photo gallery order is added later
- **WHEN** a future photo gallery block needs reorderable photos
- **THEN** Office Graph SHOULD add typed gallery photo placement tables with
  concrete gallery and photo foreign keys while reusing the same placement,
  ordering, validity, and derived-ordinal semantics

### Requirement: Fractional Manual Ordering
Office Graph SHALL use sortable position keys for manual ordering so inserts
and moves do not require renumbering sibling rows.

#### Scenario: Item is inserted between siblings
- **WHEN** an ordered item is inserted between two existing siblings
- **THEN** Office Graph MUST be able to assign a sortable position key between
  the neighboring keys without updating every sibling row

#### Scenario: Dense numbering is displayed
- **WHEN** users or APIs need numbered list positions, gallery indexes, slide
  numbers, or dense card order
- **THEN** those ordinal values MUST be derived from sorted placement state
  rather than stored as the durable ordering source of truth

### Requirement: Reordering Is Versioned Placement State
Office Graph SHALL treat reordering as a placement-version change rather than
as a content-version change.

#### Scenario: Item is moved
- **WHEN** a document block, list item, task, card, or gallery photo is moved
  without changing its content
- **THEN** Office Graph MUST create, close, or supersede placement-version
  state for the move without creating new content-version rows for unchanged
  content

### Requirement: Ordering Strategies Are Extensible
Office Graph SHALL allow new ordering strategies without changing the base
ordered-placement identity contract.

#### Scenario: New ordered surface needs a different structure
- **WHEN** a later feature needs grid placement, grouped or swimlane ordering,
  append-only sequencing, priority ranking, or topological ordering
- **THEN** Office Graph MUST add strategy-specific columns or typed extension
  tables while preserving stable collection, placement, item, and revision
  semantics
