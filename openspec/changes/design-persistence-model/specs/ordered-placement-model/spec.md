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

### Requirement: Reordering Does Not Change Content
Office Graph SHALL treat reorder actions as ordering state changes rather than
content edits when the item content does not change.

#### Scenario: Ordered item is moved
- **WHEN** a task, list item, or rich text block is moved without changing its
  content
- **THEN** Office Graph MUST preserve operation correlation for the move and
  MUST NOT create a new content revision for unchanged content
