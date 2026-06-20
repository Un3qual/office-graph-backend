## ADDED Requirements

### Requirement: Cross-Scope Agent Run Authority
Office Graph SHALL govern automatic and delegated agent runs through explicit
run authority rather than unrestricted user inheritance.

#### Scenario: Agent run starts from a signal
- **WHEN** an agent run starts from a signal, selected graph item, webhook
  source, integration event, scheduled policy, or user delegation
- **THEN** the run must record its initial authority basis, triggering
  principal, agent principal, organization, starting scopes, capabilities,
  autonomy policy, and resource sensitivity labels

#### Scenario: Automatic run has no direct human starter
- **WHEN** an agent run is started by an automatic trigger rather than a human
  user
- **THEN** the run must derive authority from trigger policy, agent
  configuration, organization policy, integration or webhook-source scope, and
  any required approvals

### Requirement: Context Expansion Requests
Office Graph SHALL require context expansion requests when an agent needs
access outside its current authorized scope.

#### Scenario: Agent needs backend context for frontend crash
- **WHEN** an agent investigating a frontend crash needs backend, devops,
  repository, deployment, feature-flag, or prior decision context
- **THEN** the agent must request expansion with target scopes, reason,
  requested capabilities, resource sensitivity labels, and whether access is
  read-only, proposal-only, or write-capable

#### Scenario: Expansion is evaluated
- **WHEN** a context expansion request is evaluated
- **THEN** policy must allow it, deny it, redact context, return summaries,
  require approval, or create a temporary explicit grant with durable
  decision traceability when policy-sensitive

#### Scenario: Cross-organization expansion is requested
- **WHEN** an agent requests access across organization boundaries
- **THEN** the request must be treated as exceptional and require explicit
  policy support, auditability, and human approval unless a future accepted
  design defines a safer automated path

### Requirement: Agent Autonomy Envelopes
Office Graph SHALL let organizations approve bounded autonomy envelopes for
agents so safe repeated work can proceed without per-action human babysitting.

#### Scenario: Agent autonomy is configured
- **WHEN** an admin, owner, or authorized agent operator configures an agent,
  workflow, or work packet for automatic execution
- **THEN** the configuration must define allowed scopes, tools,
  sensitivity labels, action types, runtime or budget limits, data volume limits,
  and whether the agent is read-only, proposal-only, write-capable, or
  external-write-capable

#### Scenario: Low-risk expansion is requested
- **WHEN** an agent requests same-scope or directly related read-only context
  with low or normal sensitivity, no secret access, no export, no external
  write, and no policy ambiguity
- **THEN** organization policy may auto-approve the expansion inside the
  configured autonomy envelope and record the decision when required

#### Scenario: High-risk expansion is requested
- **WHEN** an agent requests sensitive context, broad cross-workspace access,
  credential use, write-capable authority, external comments, external
  provider mutations, production-affecting actions, exports, destructive
  actions, or high-risk proposed graph changes
- **THEN** Office Graph must require an approval gate unless an explicit
  accepted policy configuration safely permits the action

#### Scenario: Approval fatigue is detected
- **WHEN** users repeatedly approve equivalent context expansions for the same
  agent, scope, sensitivity label, capability, and limits
- **THEN** Office Graph should surface a policy review opportunity to create a
  narrower auto-approval rule rather than training users to approve repetitive
  prompts without reading them

### Requirement: Temporary Scoped Grants For Runs
Office Graph SHALL support temporary scoped grants for approved agent runs and
context expansions.

#### Scenario: Temporary grant is created
- **WHEN** policy or a human approval permits a run to access additional
  scopes
- **THEN** the system must record principal, run, requested scopes, approved
  scopes, capability, reason, creator or approving principal, expiration,
  revocation state, and audit trail

#### Scenario: Run ends
- **WHEN** a run completes, fails, is cancelled, or exceeds its expiration
  window
- **THEN** temporary run-scoped grants must expire or be revoked according to
  policy

### Requirement: Approval Gates As Governed Requirements
Office Graph SHALL model human approval requirements as governed requirements
that can produce evidence or satisfy verification checks, rather than
side-channel comments or status flags.

#### Scenario: Work requires final approval
- **WHEN** a task, work packet, proposed graph change, PR merge, external
  write, deployment, waiver, sensitive data access, or cross-scope expansion
  requires human approval
- **THEN** the system must represent the approval gate with required
  capability, scope relationship, approver count, expiration or reapproval
  rules, and evidence or verification-check satisfaction requirements

#### Scenario: Approval is recorded
- **WHEN** a human approves or rejects an approval gate
- **THEN** Office Graph must record principal, authority basis, related graph
  item, related run, related proposed graph change, related revision or
  operation when available, reason when available, timestamp, and audit trail

### Requirement: Company-Structure-Derived Approvals
Office Graph SHALL resolve approval requirements against the customer's
existing company structure where possible.

#### Scenario: Approval candidates are resolved
- **WHEN** an approval gate requires an eligible approver
- **THEN** Office Graph must be able to resolve candidates from SCIM or IdP
  groups, departments, org units, manager relationships, team owners,
  workspace or project admins, data owners, integration owners, code owners,
  security, compliance, finance, legal roles, custom roles, and explicit
  grants

#### Scenario: Approval rule is evaluated
- **WHEN** an approval rule is evaluated
- **THEN** authorization must consider required capability, relationship,
  scope, sensitivity label, approver count, expiration, reapproval rules, and
  separation-of-duties constraints rather than relying on hardcoded named
  approvers

#### Scenario: Finance-sensitive export requires approval
- **WHEN** a user or agent requests export of a finance-sensitive artifact
- **THEN** policy may require approval from an eligible finance data owner or
  finance manager who is not the requester, implementer, or agent delegator

### Requirement: Separation Of Duties
Office Graph SHALL support separation-of-duties rules for approval gates.

#### Scenario: Author cannot final approve
- **WHEN** policy states that an author, requester, agent delegator, or
  implementer cannot satisfy a final approval gate
- **THEN** the approval gate must remain unsatisfied until an eligible
  principal with the required capability and scope relationship approves it

#### Scenario: Team lead approval is required
- **WHEN** policy requires team lead, code owner, manager, incident commander,
  security reviewer, finance approver, or release owner approval
- **THEN** authorization must evaluate the approver's scoped role, custom role,
  grant, relationship, capability, and separation-of-duties eligibility

### Requirement: Provider-Native Approval Import
Office Graph SHALL be able to import provider-native approvals as evidence
without making external systems the source of truth for all approval semantics.

#### Scenario: PR approval is imported
- **WHEN** a GitHub, GitLab, design tool, finance tool, ticketing tool, or
  other provider approval is imported
- **THEN** Office Graph may link it as evidence for a graph-native approval
  check after validating source, actor mapping, scope, and policy relevance

#### Scenario: Office Graph approval is required
- **WHEN** graph-native policy requires an approval that the external provider
  cannot express
- **THEN** the Office Graph approval gate must remain authoritative even if
  external provider status appears complete
