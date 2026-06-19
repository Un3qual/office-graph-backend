## ADDED Requirements

### Requirement: Unified Principal Model
Office Graph SHALL authorize humans, agents, service accounts, integrations,
webhook sources, system jobs, and external executors through a unified
principal model.

#### Scenario: Actor attempts a governed action
- **WHEN** any actor attempts to read, write, execute, approve, export, use a
  tool, call an integration, or receive graph context
- **THEN** the authorization boundary must evaluate that actor as a principal
  with type, lifecycle state, tenant, scopes, memberships, capabilities, and
  policy context

#### Scenario: Agent acts for a user or workflow
- **WHEN** an agent acts on behalf of a user, workflow, automatic trigger, or
  work packet
- **THEN** the agent must be evaluated as its own principal with constrained
  delegation rather than receiving unrestricted user authority

### Requirement: Initial Scoped Role Vocabulary
Office Graph SHALL define a small initial scoped role vocabulary for coarse
enterprise administration and default access.

#### Scenario: Role vocabulary is seeded
- **WHEN** the initial role vocabulary is designed
- **THEN** it must include org owner, org admin, workspace admin, project
  admin, member, viewer, auditor, integration admin, and agent operator roles
  or explicitly justify any omission

#### Scenario: Role is assigned
- **WHEN** a role is assigned to a principal
- **THEN** the assignment must include actor, target principal, role, scope,
  creator, creation time, lifecycle state, and audit trail

### Requirement: MVP Custom Role Model
Office Graph SHALL model custom roles in the MVP authorization data model even
if the first custom-role management UI is minimal.

#### Scenario: Custom role is defined
- **WHEN** an organization defines a custom role
- **THEN** the role must be represented as a typed scoped capability bundle
  with organization ownership, name, lifecycle state, included capabilities,
  scope applicability, creator, timestamps, and audit trail

#### Scenario: External group maps to authorization
- **WHEN** an SSO claim, SCIM group, IdP group, or customer role is imported
  or configured
- **THEN** Office Graph must map it into internal teams, scoped role
  assignments, custom roles, grants, or capabilities rather than trusting the
  external name as direct product authority

#### Scenario: Custom role UI is absent
- **WHEN** the first product release does not expose a polished custom-role UI
- **THEN** the schema, domain actions, tests, and admin/bootstrap paths must
  still support custom roles and external group mappings

### Requirement: Capability Vocabulary
Office Graph SHALL use named capabilities as the durable policy vocabulary
under roles, explicit grants, agent permissions, and integration scopes.

#### Scenario: Capability is evaluated
- **WHEN** an actor attempts a governed action
- **THEN** the authorization boundary must evaluate the relevant named
  capability in addition to role, relationship, classification, and policy
  facts

#### Scenario: Initial capability set is designed
- **WHEN** the initial capability set is defined
- **THEN** it must cover graph item access, membership management,
  integration management, credential management, agent execution, agent
  approval, work packet modification, proposed graph change approval, check
  waivers, sensitive artifact access, exports, external comments, external
  writes, context expansion, approval gate satisfaction, retention, legal
  hold, and audit-log visibility

### Requirement: Typed Scope Inheritance
Office Graph SHALL express tree-like permissions through typed scope
inheritance rather than wildcard permission strings.

#### Scenario: Frontend lead receives inherited authority
- **WHEN** a principal receives a role assignment or grant on a scope such as
  frontend with descendant inheritance enabled
- **THEN** authorization may apply the relevant capabilities to typed
  descendant scopes such as frontend iOS or frontend web according to explicit
  scope hierarchy policy

#### Scenario: Permission is explained
- **WHEN** authorization allows an action through inherited scope authority
- **THEN** the decision explanation and any durable decision record must
  identify the original assignment or grant, inherited scope path, capability,
  and resource scope

#### Scenario: Wildcard permission is proposed
- **WHEN** a permission pattern such as `frontend.*` is needed
- **THEN** the design must represent it using typed scope records and
  descendant inheritance flags rather than string-prefix matching

### Requirement: Explicit Grants For Exceptions
Office Graph SHALL represent exceptional access as explicit grants rather than
implicit graph access or ad hoc sharing.

#### Scenario: Cross-scope exception is granted
- **WHEN** a user, agent, service account, integration, or external reviewer
  receives access outside default policy
- **THEN** the system must record principal, resource or scope, capability,
  reason, creator, creation time, optional expiration, optional approval
  requirement, lifecycle state, and audit trail

#### Scenario: Grant is used
- **WHEN** authorization allows an action because of an explicit grant
- **THEN** the authorization result and any durable decision record must
  identify the grant as part of the permission basis

### Requirement: Resource Classification Policy
Office Graph SHALL model resource classifications explicitly and use them in
authorization, redaction, AI context assembly, audit, and export decisions.

#### Scenario: Classified resource is accessed
- **WHEN** a resource classified as restricted, secret, source code,
  customer-sensitive, finance-sensitive, legal-sensitive, security-sensitive,
  team-restricted, initiative-scoped, project-scoped, workspace-scoped, or
  org-internal is accessed
- **THEN** policy must be able to evaluate the classification without parsing
  generic JSON metadata

#### Scenario: Classification affects graph context
- **WHEN** a graph projection, embedded conversation, work packet, or agent
  context package includes classified resources
- **THEN** the system must apply classification-specific visibility,
  redaction, audit, export, and AI data-control rules

### Requirement: Explainable Authorization Decisions
Office Graph SHALL produce authorization decisions that can explain allows,
denials, redactions, placeholders, approval requirements, and escalations.

#### Scenario: Action is denied or restricted
- **WHEN** authorization denies, redacts, placeholders, approval-gates, or
  escalates an action
- **THEN** the decision must identify the relevant limiting factors in terms
  of role, capability, relationship, classification, grant, organization
  policy, inherited scope path, tool scope, integration scope, work packet
  policy, approval gate, separation-of-duties rule, or agent capability

#### Scenario: Agent action is allowed
- **WHEN** an agent action is allowed
- **THEN** the decision must be explainable as the intersection of delegator
  permission, agent capability, work packet autonomy policy, tool or
  integration scope, organization policy, resource classification policy, and
  any approved context expansion or temporary grant

### Requirement: Durable Authorization Decision Records
Policy-sensitive authorization decisions SHALL be recorded durably when they
affect sensitive data, external writes, tool use, approvals, waivers, exports,
credentials, grants, or cross-boundary access.

#### Scenario: Sensitive decision occurs
- **WHEN** authorization allows, denies, redacts, approval-gates, or escalates
  a policy-sensitive action
- **THEN** the system must be able to record actor, delegator when applicable,
  action, resource, tenant, scope, policy context, result, reason, request
  source, trace identifier, related grant, related run, related approval, and
  policy version when available

#### Scenario: Cross-scope expansion is decided
- **WHEN** an agent run, integration, or human workflow requests access across
  team, component, repository, workspace, initiative, or organization scopes
- **THEN** the decision record must capture requested scopes, approved scopes,
  denied scopes, redactions, temporary grants, approval requirements, and
  authority basis when the action is policy-sensitive

#### Scenario: Low-risk read occurs
- **WHEN** a normal low-risk read occurs against a resource that is not marked
  for durable read audit
- **THEN** the system may rely on operational logging rather than creating a
  durable authorization decision record

### Requirement: Policy Bundle Versions
Office Graph SHALL represent authorization policy as immutable versioned rule
sets that interpret authorization facts for a request.

#### Scenario: Policy-sensitive action is evaluated
- **WHEN** a policy-sensitive authorization decision is made for an actor,
  action, resource, scope, classification, tool, integration, or run context
- **THEN** the decision must be able to reference the effective policy bundle
  version, bundle digest, relevant component policy versions, relevant fact
  references, result, and explanation

#### Scenario: Permission fact changes
- **WHEN** a role assignment, custom role definition, explicit grant,
  classification, group membership, ownership link, manager relationship, or
  agent capability changes
- **THEN** the change must be modeled as an authorization fact change rather
  than as a standalone policy unless it changes the rule set that interprets
  facts

#### Scenario: Historical decision is reviewed
- **WHEN** an auditor, admin, security reviewer, or support workflow reviews an
  old authorization decision
- **THEN** Office Graph must preserve enough policy version and fact reference
  information to explain the decision under the rules that were effective when
  the decision was made without copying a giant policy blob into every
  decision record
