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
- **THEN** they MUST consider inbox, question queue, focused node
  neighborhood, blocker view, dependency view, workstream board, work packet
  context, review surface, and evidence chain projections

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
- **THEN** it MAY group or filter by normalized status families while
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
