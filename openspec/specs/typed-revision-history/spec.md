# typed-revision-history Specification

## Purpose
TBD - created by archiving change design-revision-audit-soft-delete. Update Purpose after archive.
## Requirements
### Requirement: Aggregate-Aware Typed Revisions
Office Graph SHALL preserve meaningful product state changes through typed,
aggregate-aware revision records rather than one opaque JSON-backed versions
table.

#### Scenario: Mutable product record changes
- **WHEN** a graph item, task, requirement, decision, check, evidence item,
  conversation, review finding, provider-neutral product record, or sensitive
  domain record changes
- **THEN** Office Graph MUST record typed revision history with actor or
  source, operation correlation, timestamp, reason when available, affected
  fields or child components, supersession or parent revision, and concrete
  resource references

#### Scenario: Large payload already has a durable owner
- **WHEN** a revision needs to refer to rich text, an artifact, a raw archive,
  a derived render, or an external reference
- **THEN** the revision MUST reference the owning record instead of copying the
  full payload into revision history

#### Scenario: First migration revision tables are selected
- **WHEN** the first backend migrations model graph items, rich text documents,
  ordered placements, conversations, messages, review findings, evidence, or
  provider-neutral imported product records
- **THEN** Office Graph MUST give those high-value native or reconstruction-
  sensitive aggregates bespoke typed revision tables or concrete revision
  modules, while simpler metadata/settings changes MAY use shared typed
  revision helper conventions with concrete foreign keys and typed changed
  fields

### Requirement: Revision Reconstruction
Office Graph SHALL make revision history reconstructable for product state that
needs review, restore, audit support, or historical context.

#### Scenario: Historical state is requested
- **WHEN** an authorized user, agent, export, or investigation requests the
  state of a mutable product record at a prior revision
- **THEN** Office Graph MUST be able to reconstruct meaningful state from typed
  revisions, referenced content records, and supersession relationships without
  parsing a generic versions JSON blob

#### Scenario: Rich text or ordered placement changes
- **WHEN** rich text content, rich text block order, task ordering, plan section
  ordering, or another versioned placement changes
- **THEN** revision history MUST link to the rich text revision or placement
  version state that reconstructs the change without creating unrelated
  content revisions

#### Scenario: Task title and description change together
- **WHEN** a user edits a task title and one word of the task description in
  one save
- **THEN** the task aggregate revision MUST capture the title change and
  reference the rich text document revision for the description change, with
  both records referencing the same operation correlation identifier

### Requirement: Revision Concern Separation
Office Graph SHALL keep revision records distinct from audit records, domain
events, run events, external sync events, authorization decision records, and
raw payload archives.

#### Scenario: Product action creates multiple historical records
- **WHEN** a product action changes state, requires audit, emits a domain
  event, writes a run event, or records external sync state
- **THEN** each concern MUST write its own typed record and MAY share an
  operation correlation identifier without duplicating another record's payload
