## ADDED Requirements

### Requirement: Addressable Graph Item Contract
Office Graph SHALL make every meaningful work object addressable through a
shared graph item contract.

#### Scenario: Graph item is created
- **WHEN** a signal, requirement, task, question, decision, check, evidence
  item, artifact, run, work packet, conversation, external reference, document
  section, or plan section is created as graph-addressable work
- **THEN** it MUST have stable graph identity, item type, organization scope,
  workspace scope when applicable, lifecycle state, classification, owner or
  source, provenance, and relationship participation metadata sufficient for
  graph traversal and scoped conversation

#### Scenario: Graph item is selected
- **WHEN** a user or agent selects an addressable graph item
- **THEN** Office Graph MUST be able to reference that item in conversations,
  reviews, provenance records, projections, work packets, checks, evidence,
  and future automation

### Requirement: Department-Neutral Core Item Types
Office Graph SHALL define a small department-neutral core graph item taxonomy.

#### Scenario: Core taxonomy is used
- **WHEN** the core graph model classifies work
- **THEN** it MUST support signals, requirements, tasks, questions, decisions,
  checks, evidence, artifacts, runs, work packets, conversations, external
  references, and addressable document or plan sections without making
  software-specific concepts mandatory

#### Scenario: First executable graph slice is built
- **WHEN** the first backend walking skeleton is implemented
- **THEN** it MUST support manual intake signal, task, review finding,
  required verification check, evidence item, and verified completion as the
  first graph-addressable slice before expanding to the full taxonomy

#### Scenario: Department-specific workflow is added
- **WHEN** a design, marketing, social, finance, operations, leadership, or
  engineering workflow adds specialized data
- **THEN** it MUST attach specialized records to the shared taxonomy rather
  than redefining a separate graph ontology for that department

### Requirement: Typed Resources Own Business Meaning
Office Graph SHALL keep type-specific business meaning in typed resources and
domain actions rather than in opaque graph properties.

#### Scenario: Type has domain behavior
- **WHEN** a graph-addressable concept has its own fields, validations,
  lifecycle transitions, authorization rules, query patterns, revision needs,
  or domain actions
- **THEN** it MUST be modeled as or promoted to a typed resource that
  participates in the graph contract

#### Scenario: Generic metadata is proposed
- **WHEN** a core behavior, lifecycle rule, authorization fact, validation
  rule, or queryable product field is proposed as generic JSON metadata
- **THEN** the design MUST prefer typed fields, join tables, or typed resources
  unless a later persistence design accepts a narrow raw-payload exception

### Requirement: Type-Specific Lifecycles And Projection Status Families
Office Graph SHALL let typed resources own their lifecycle while exposing
normalized status families for graph projections.

#### Scenario: Item lifecycle changes
- **WHEN** a question, task, check, evidence item, run, work packet, or
  conversation changes state
- **THEN** the state transition MUST be governed by the item type's lifecycle
  rules rather than by one universal graph status enum

#### Scenario: Projection filters by status
- **WHEN** a graph projection filters or groups mixed item types
- **THEN** it MAY use normalized status families such as new, open, blocked,
  waiting, in progress, done, verified, failed, superseded, archived, or
  deleted as read-model categories derived from type-specific state

### Requirement: Graph Items Preserve Provenance
Office Graph SHALL preserve provenance for graph items created by humans,
agents, integrations, imports, generated UI, and system jobs.

#### Scenario: Item is generated or imported
- **WHEN** a graph item is created from a manual action, agent output,
  integration event, imported provider object, generated UI action, or system
  job
- **THEN** the item MUST retain source type, source principal when available,
  related run or integration event when available, and enough provenance for
  later review, revision, and audit designs

#### Scenario: Item is superseded
- **WHEN** a graph item is superseded, split, merged, archived, or deleted
- **THEN** the graph model MUST preserve enough provenance to explain the
  relationship between the old item and replacement or terminal state
