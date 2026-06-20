## ADDED Requirements

### Requirement: Ordered Placement V1 Scope
Office Graph SHALL keep first-cut ordering explicit and domain-owned instead
of building a generic ordered-placement API before usage proves it.

#### Scenario: First backend cut needs ordering
- **WHEN** the walking skeleton needs ordered task lists or rich text blocks
- **THEN** Office Graph MUST use explicit domain-owned ordering fields or typed
  placement tables for those domains rather than a broad reusable generic
  ordering subsystem

#### Scenario: Future ordered surfaces are proposed
- **WHEN** galleries, slides, swimlanes, grid placement, generic ordered
  collections, dense ordinal projections, rebalancing jobs, or topological
  ordering are needed
- **THEN** they MUST be designed in a future ordered placement implementation
  change after real product usage defines the required semantics

### Requirement: No Polymorphic Placement Foreign Keys
Office Graph SHALL NOT use polymorphic local `owner_type`/`owner_id` or
`item_type`/`item_id` pairs as the durable ordering model.

#### Scenario: Domain-owned ordering is implemented
- **WHEN** a task list, rich text block list, or other v1 ordered structure is
  persisted
- **THEN** owner and item references MUST use concrete graph identity or typed
  domain foreign keys rather than polymorphic local type/id pairs

### Requirement: Task List Ordering
Office Graph SHALL support explicit task-list ordering for the first walking
skeleton.

#### Scenario: Tasks are ordered inside a work container
- **WHEN** tasks are displayed or updated in an ordered list for an initiative,
  workstream, review finding, or work packet preparation flow
- **THEN** the task-list ordering MUST be owned by the relevant task/work
  container domain and MUST preserve concrete references, lifecycle state, and
  operation correlation for reorder actions

### Requirement: Rich Text Block Ordering
Office Graph SHALL support typed rich text block ordering in the first rich
text schema.

#### Scenario: Rich text blocks are ordered
- **WHEN** a rich text document stores multiple blocks
- **THEN** block order MUST be represented by the rich text/content domain
  with concrete document and block references, current ordering state, and
  semantic document revision linkage

### Requirement: Ordered Placement V1 Extension Contract
Office Graph SHALL keep v1 ordering domain-owned while preserving a clear path
to future shared ordering behavior.

#### Scenario: V1 ordered structures are persisted
- **WHEN** task-list ordering or rich text block ordering is implemented in the
  first backend cut
- **THEN** the chosen fields or typed placement tables MUST carry stable owner
  references, stable item references, sortable position keys, lifecycle state,
  operation correlation, and optimistic conflict metadata compatible with a
  later shared placement service or library

#### Scenario: Future generic placement behavior is introduced
- **WHEN** a future accepted ordered placement implementation adds reusable
  placement APIs, galleries, slides, swimlanes, grid placement, topological
  ordering, dense ordinal projections, or rebalance jobs
- **THEN** it MUST wrap, extend, or migrate from the v1 domain-owned ordering
  records through additive typed tables and backfills rather than requiring a
  wholesale rewrite to polymorphic local owner/item references

#### Scenario: Ordering strategy evolves
- **WHEN** a domain outgrows the first sortable position-key strategy
- **THEN** the new strategy MUST preserve existing collection or owner
  identity, item identity, lifecycle state, operation correlation, and audit or
  revision linkage so historical moves remain explainable

### Requirement: Reordering Does Not Change Content
Office Graph SHALL treat reorder actions as ordering state changes rather than
content edits when the item content does not change.

#### Scenario: Ordered item is moved
- **WHEN** a task, list item, or rich text block is moved without changing its
  content
- **THEN** Office Graph MUST preserve operation correlation for the move and
  MUST NOT create a new content revision for unchanged content
