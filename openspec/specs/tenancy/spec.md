# tenancy Specification

## Purpose
Define organization tenancy, workspace and initiative scopes, graph access boundaries, explicit scope columns, and enterprise organization vocabulary.

## Requirements

### Requirement: Organization Root Tenant
Office Graph SHALL use organization as the root tenant for customer-owned
product data, policy, audit, identity mapping, export, retention, and deletion
boundaries.

#### Scenario: Durable customer record is created
- **WHEN** a durable customer-owned product record is created
- **THEN** the record must be associated with an organization directly or
  through a strict owned parent whose organization cannot be ambiguous

#### Scenario: Enterprise policy is evaluated
- **WHEN** organization-level policy is evaluated for a user, agent,
  integration, service account, webhook source, or system job
- **THEN** the organization must be the root policy boundary for the decision

### Requirement: Workspace And Initiative Visibility Scopes
Office Graph SHALL use workspace and initiative/project as default visibility
and execution scopes inside an organization.

#### Scenario: Graph item visibility is evaluated
- **WHEN** an actor attempts to view a graph item
- **THEN** authorization must consider the item's organization, workspace, and
  initiative/project scopes before exposing the item or its details

#### Scenario: Work is prepared for execution
- **WHEN** a work packet, run, verification check, or agent execution is
  prepared
- **THEN** the system must identify the applicable organization and workspace
  and should identify the applicable initiative/project when the work belongs
  to an initiative-scoped execution boundary

### Requirement: Initiative Project Semantics
Office Graph SHALL treat project as a customer-facing alias for an initiative
or bounded work container, not as a synonym for team, component, repository,
or task.

#### Scenario: Cross-functional work is modeled
- **WHEN** work such as migrating a mobile app, adding image uploads, launching
  a campaign, or resolving a cross-team incident requires requirements,
  discussion, tasks, approvals, and verification across multiple teams
- **THEN** the work should be modeled as an initiative/project with related
  workstreams, graph items, teams, components, repositories, artifacts, and
  checks

#### Scenario: Team or component is modeled
- **WHEN** a concept such as frontend, backend, iOS, devops, repository,
  service, or product area is modeled
- **THEN** it must be represented as a team, component, code area, repository,
  service, or other related scope/resource rather than being forced to be a
  project

#### Scenario: Small work item is modeled
- **WHEN** a bug fix, support request, review finding, or small task is
  modeled
- **THEN** it should be represented as a signal, task, issue, check,
  workstream item, or graph item unless it grows into a larger initiative

### Requirement: Row-Based Tenant Isolation For MVP
Office Graph SHALL use row-based tenant isolation for the MVP while preserving
a path to stronger enterprise isolation options.

#### Scenario: Table stores tenant-owned data
- **WHEN** a table stores tenant-owned product data
- **THEN** the design must include tenant or scope columns, baseline indexes,
  and domain authorization checks that enforce organization isolation

#### Scenario: Stronger isolation is requested later
- **WHEN** a future enterprise customer requires database, schema, deployment,
  residency, or row-level-security isolation
- **THEN** the design must be able to evaluate that option without redefining
  organization, workspace, and initiative/project semantics

### Requirement: Graph Is Not An Access-Granting Tenant
Office Graph SHALL NOT treat graph membership or graph edges as automatic
access grants.

#### Scenario: Graph projection spans scopes
- **WHEN** a graph projection spans multiple initiatives, workstreams,
  workspaces, teams, components, repositories, integrations, or external
  sources
- **THEN** every included node, edge, artifact, external reference, revision,
  and summary must be filtered through authorization before exposure

#### Scenario: Actor can view an edge but not the target
- **WHEN** an actor can view a relationship to a restricted graph item but
  cannot view the target item
- **THEN** the response must hide the target, expose a restricted placeholder,
  or show a policy-approved redacted summary

### Requirement: Explicit Scope Columns
Durable Office Graph records SHALL identify their applicable scopes explicitly
enough for authorization, indexing, export, retention, and future isolation.

#### Scenario: Durable table is designed
- **WHEN** a durable table is introduced for graph items, artifacts, runs,
  revisions, audit records, credentials, integration data, or verification
  data
- **THEN** the design must state which organization, workspace, initiative,
  project alias, workstream, team, component, repository, integration,
  external source, graph, or artifact scopes apply

#### Scenario: Scope is inherited
- **WHEN** a record inherits scope from a parent record instead of storing all
  scope columns directly
- **THEN** the ownership path must be strict, queryable, and safe for
  authorization and export decisions

### Requirement: Hierarchical Scope Inheritance
Office Graph SHALL support typed hierarchical scopes for organization
structures such as teams, subteams, components, services, repositories,
departments, org units, workspaces, and initiatives.

#### Scenario: Permission applies to descendants
- **WHEN** a role assignment or grant is configured to apply to descendant
  scopes
- **THEN** authorization must apply the assignment only through explicit typed
  scope inheritance rather than wildcard permission strings

#### Scenario: Graph edge connects two scopes
- **WHEN** a graph edge connects items from different teams, components,
  repositories, initiatives, or workspaces
- **THEN** the edge must not create inherited permission by itself

#### Scenario: Organization structure changes
- **WHEN** a team, subteam, component, or repository moves within a hierarchy
- **THEN** inherited access must remain explainable, auditable, and safe to
  recalculate from typed scope relationships

### Requirement: Enterprise-Familiar Organization Vocabulary
Office Graph SHALL expose conventional enterprise organization concepts in
setup and administration surfaces where those concepts map cleanly to the
domain model.

#### Scenario: IT admin configures organization structure
- **WHEN** an IT admin configures imported or local structure
- **THEN** Office Graph should expose familiar concepts such as departments,
  org units, teams, groups, managers, owners, workspaces, roles, custom roles,
  permissions, and policies rather than requiring graph-specific vocabulary

#### Scenario: Backend concept has no conventional equivalent
- **WHEN** a backend-only concept such as principal, capability, scope, graph
  projection, autonomy envelope, policy bundle, or context expansion request
  has no clean conventional enterprise term
- **THEN** the concept may remain explicit in the domain model, API, and
  engineering documentation while user-facing surfaces translate it where
  practical
