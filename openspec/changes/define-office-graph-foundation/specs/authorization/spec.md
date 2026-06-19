## ADDED Requirements

### Requirement: Unified Principal Model

Office Graph SHALL authorize humans, agents, service accounts, integrations,
webhook sources, and system processes through a unified principal model.

#### Scenario: Actor attempts an action

- **WHEN** any actor attempts to read, write, execute, approve, export, or use
  a tool
- **THEN** the authorization boundary must evaluate the actor as a principal
  with type, scope, membership, capabilities, and policy context

### Requirement: Hybrid Enterprise Authorization

Office Graph SHALL use a hybrid authorization model rather than plain
roles-only RBAC.

#### Scenario: Policy is evaluated

- **WHEN** access is checked
- **THEN** the decision must be able to combine coarse RBAC roles, contextual
  ABAC facts, relationship-based graph and team checks, capability
  permissions, and explicit grants

#### Scenario: Exceptional collaboration is needed

- **WHEN** a user, team, agent, or integration needs access outside default
  policy
- **THEN** the system must represent that access as an explicit grant with
  scope, capability, reason, actor, time bounds when applicable, and audit
  trail

### Requirement: Scoped Visibility And Redaction

Default graph visibility SHALL be workspace/project scoped, and graph links
SHALL NOT automatically grant access to connected records.

#### Scenario: Authorized item links to restricted item

- **WHEN** an actor can view one graph item that links to another item outside
  their permitted scope
- **THEN** the system must hide the connected item, show a restricted
  placeholder, or provide a policy-approved redacted summary

#### Scenario: Agent context package is assembled

- **WHEN** context is assembled for an agent or embedded conversation
- **THEN** every included node, edge, artifact, conversation, external
  reference, and revision must be filtered through authorization

### Requirement: Agent Effective Permissions

Agent effective permissions SHALL be the intersection of delegator permission,
agent capability, work packet autonomy policy, tool or integration scope, and
organization policy.

#### Scenario: Delegated agent action is requested

- **WHEN** an agent acts on behalf of a user or workflow
- **THEN** the agent must not receive broader authority than the intersection
  of all relevant permission constraints

#### Scenario: Tool access differs from graph access

- **WHEN** an agent can read graph context
- **THEN** that read permission must not imply permission to use write tokens,
  post external comments, push commits, waive checks, export data, or call
  provider APIs

### Requirement: Relational Permission Data

Authorization data SHALL be modeled relationally and explicitly.

#### Scenario: Permission storage is designed

- **WHEN** schemas are created for principals, roles, memberships,
  capabilities, grants, tool permissions, integration scopes, autonomy
  policies, or policy decisions
- **THEN** core policy state must use typed tables and columns rather than JSON
  claims or generic metadata blobs

### Requirement: Authorization Decision Records

Policy-sensitive authorization decisions SHALL be auditable.

#### Scenario: Sensitive action is allowed or denied

- **WHEN** an action affects sensitive data, agent tool use, external writes,
  approval gates, waivers, exports, credentials, or cross-boundary access
- **THEN** the system must be able to record actor, action, resource, policy
  context, result, reason, request source, and related run or approval
