# work-containers Specification

## Purpose

Define initiatives, workstreams, related scopes/resources, small-work behavior,
and explicit scope requirements for Office Graph work containers.

## Requirements

### Requirement: Initiative Work Containers

Office Graph SHALL model initiatives as bounded work containers for
business, product, operational, or cross-functional outcomes inside a
workspace.

#### Scenario: Cross-functional outcome is created

- **WHEN** work such as a mobile migration, image-upload feature, campaign
  launch, finance reconciliation, or cross-team incident requires discussion,
  requirements, tasks, approvals, and verification across multiple groups
- **THEN** the work MUST be representable as an initiative scoped to
  an organization and workspace

#### Scenario: Project label is shown to users

- **WHEN** a user-facing surface presents an initiative
- **THEN** the surface MAY use the familiar label project while preserving
  initiative semantics in the domain model and API documentation

### Requirement: Workstream Execution Lanes

Office Graph SHALL model workstreams as team-, domain-, or phase-specific
execution lanes inside an initiative.

#### Scenario: Initiative has multiple execution lanes

- **WHEN** an initiative includes backend implementation, frontend
  implementation, design review, security review, launch, finance approval, or
  operations follow-up
- **THEN** each lane MUST be representable as a workstream with organization,
  workspace, initiative, owner or source, lifecycle state, and related
  scopes when available

#### Scenario: Work item is assigned to a workstream

- **WHEN** a task, question, check, evidence item, run, work packet, or review
  finding belongs to a specific execution lane
- **THEN** the item MUST be able to reference the applicable workstream without
  losing its initiative and workspace scope

### Requirement: Teams And Resources Are Not Projects By Default

Office Graph SHALL attach teams, departments, org units, components,
repositories, services, campaigns, finance accounts, design systems, and
external systems to work containers as related scopes or resources rather than
forcing them to be projects.

#### Scenario: Engineering area is modeled

- **WHEN** a concept such as frontend, backend, iOS, devops, repository,
  service, component, or code area is modeled
- **THEN** it MUST be represented as a related team, component, repository,
  service, or scope unless it represents a bounded business outcome

#### Scenario: Non-engineering resource is modeled

- **WHEN** a design system, campaign, social calendar, finance account,
  department, org unit, document collection, or external system participates in
  an initiative
- **THEN** it MUST be attachable to the initiative or workstream as a
  related resource or scope without becoming the work container itself

### Requirement: Small Work Items Remain Graph Items

Office Graph SHALL represent small work as graph items unless the work grows
into a larger initiative.

#### Scenario: Small task is created

- **WHEN** a bug fix, support request, review finding, design note, social post
  edit, finance exception, or small operations request is created
- **THEN** it MUST be representable as a signal, task, check, workstream item,
  or other graph item rather than requiring a new project

#### Scenario: Small work expands

- **WHEN** a small work item grows to require coordinated requirements,
  decisions, tasks, approvals, evidence, or verification across multiple lanes
- **THEN** the system MUST allow it to be promoted or linked into an
  initiative with provenance back to the original graph item

### Requirement: Container Scope Is Explicit

Office Graph SHALL keep work-container scope explicit enough for
authorization, indexing, export, retention, and future persistence design.

#### Scenario: Work container is created

- **WHEN** a workspace, initiative, or workstream is created
- **THEN** it MUST identify the organization scope, lifecycle state, creator or
  source, and any parent work-container scope required to interpret visibility
  and authorization

#### Scenario: Graph item belongs to work container

- **WHEN** a graph item belongs to a workspace, initiative, or
  workstream
- **THEN** the item MUST retain enough explicit or strictly inherited scope
  information to support authorization-filtered projections and future export
  decisions
