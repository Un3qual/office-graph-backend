## ADDED Requirements

### Requirement: Projections Are Filtered Views
Office Graph SHALL model graph projections as authorization-filtered views over
scoped graph data rather than as tenants or access-granting containers.

#### Scenario: Projection is requested
- **WHEN** a user, agent, integration, service account, or system job requests
  a graph projection
- **THEN** the projection MUST filter every included node, edge, artifact,
  conversation, external reference, revision summary, count, and preview
  through authorization, tenant/scope visibility, and sensitivity policy

#### Scenario: Projection spans multiple scopes
- **WHEN** a projection spans initiatives, workstreams, workspaces, teams,
  components, repositories, departments, integrations, or external sources
- **THEN** every included item MUST remain governed by its own organization,
  workspace, initiative, workstream, resource scope, and sensitivity labels

### Requirement: Restricted Projection Results
Office Graph SHALL support restricted placeholders and policy-approved
summaries when a projection reaches context the actor cannot fully view.

#### Scenario: Target item is restricted
- **WHEN** a projection includes an edge to a target item that the actor cannot
  view directly
- **THEN** the projection MUST hide the item, show a restricted placeholder, or
  show a redacted summary allowed by policy

#### Scenario: Counts include restricted items
- **WHEN** a projection computes counts, rollups, blockers, status totals, or
  neighborhood summaries across restricted data
- **THEN** the projection MUST avoid leaking sensitive information through
  aggregate values unless policy permits the aggregate disclosure

### Requirement: Initial Projection Families
Office Graph SHALL define the first projection families around practical work
surfaces instead of an arbitrary full graph canvas.

#### Scenario: MVP projection families are selected
- **WHEN** the first product projections are designed
- **THEN** they MUST include inbox, focused node neighborhood, review surface,
  evidence chain, and blocker view projections before adding dedicated
  question queue, dependency view, workstream board, work packet context, or
  arbitrary graph canvas projections

#### Scenario: Arbitrary graph canvas is requested
- **WHEN** a full arbitrary graph canvas is requested before focused
  projections prove query and interaction needs
- **THEN** the design MUST treat it as deferred unless a later accepted change
  defines concrete requirements and performance constraints

### Requirement: Projection Status Families
Office Graph SHALL allow mixed graph projections to use normalized status
families derived from type-specific lifecycle state.

#### Scenario: Mixed item projection is rendered
- **WHEN** a projection displays mixed item types such as tasks, questions,
  checks, evidence, runs, work packets, artifacts, and conversations
- **THEN** it MAY group or filter by normalized status families such as `new`,
  `open`, `needs_review`, `in_progress`, `waiting`, `blocked`, `done`,
  `verified`, `failed`, `superseded`, `archived`, and `deleted` while
  preserving each item's type-specific lifecycle state in details

#### Scenario: Status family conflicts with item lifecycle
- **WHEN** a normalized status family would imply a transition that the item
  type does not allow
- **THEN** the type-specific lifecycle MUST remain authoritative

### Requirement: Projection Context Is Explainable
Office Graph SHALL make projection membership and omissions explainable enough
for users, agents, and auditors to understand visible context.

#### Scenario: User inspects projection context
- **WHEN** a user sees an item, edge, restricted placeholder, redacted summary,
  or omitted branch in a projection
- **THEN** Office Graph MUST be able to explain the inclusion, restriction, or
  omission in terms of scope, sensitivity label, relationship type, projection
  query, and authorization result when policy permits disclosure

#### Scenario: Agent receives projection context
- **WHEN** a projection is assembled for an embedded agent, automatic agent, or
  work packet
- **THEN** the context package MUST preserve enough projection rationale for
  the agent runtime to cite context boundaries and request expansion when
  needed

### Requirement: Saved Projection Configuration Does Not Grant Access
Office Graph SHALL treat saved views, workflow views, field selections,
filters, grouping, sorting, and layout configuration as projection
configuration over scoped graph data rather than as authorization or tenancy
state.

#### Scenario: Saved view is requested
- **WHEN** a user, agent, or API client requests a saved graph view,
  workstream board, review surface, evidence chain, workflow view, or another
  named projection configuration
- **THEN** Office Graph MUST apply the saved filter, grouping, sorting, field
  selection, layout, and view number only after enforcing the same
  authorization, redaction, tombstone visibility, and sensitivity rules as an
  equivalent ad hoc projection

#### Scenario: Field configuration is exposed through an API
- **WHEN** GraphQL or JSON API exposes configurable fields, view fields,
  dynamic intake fields, or provider-derived field definitions
- **THEN** field configuration MAY be polymorphic in the API, but values that
  affect workflow state, policy, reporting, verification, or agent context
  MUST resolve to typed storage or an explicitly accepted raw/unmodeled
  exception

#### Scenario: Workflow configuration is exposed
- **WHEN** Office Graph exposes project, initiative, workstream, or workflow
  pack configuration such as enabled workflows, trigger rules, or named
  automation views
- **THEN** the configuration MUST be represented as a typed product resource
  with explicit scope and ownership and MUST NOT allow arbitrary mutation of
  graph truth tables outside approved domain actions
