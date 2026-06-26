# audit-compliance Specification

## Purpose

Define audit, operation correlation, retention, export, legal hold, visibility, and audit growth requirements.

## Requirements

### Requirement: Separate Audit Records

Office Graph SHALL keep audit records distinct from revision history, domain
events, run events, external sync events, and raw payload archives.

#### Scenario: Product record changes

- **WHEN** a product record changes
- **THEN** revision history may record the meaningful state change, but
  security or compliance-sensitive actor behavior must be represented through
  an audit record when audit policy requires it

#### Scenario: Agent run occurs

- **WHEN** an agent run produces run events, tool calls, findings, or change proposals
- **THEN** run events must not replace required audit records for sensitive
  tool use, credential use, external writes, waivers, approvals, or exports

### Requirement: Operation Correlation Records

Office Graph SHALL use shared operation or command correlation records to link
revisions, audit records, run events, domain events, and external sync events
without duplicating their payloads.

#### Scenario: Meaningful action changes product state

- **WHEN** a human, agent, integration, webhook source, service account, or
  system job performs a meaningful action that changes product state
- **THEN** the system must be able to record a shared operation or correlation
  identifier that related revisions, audit records, run events, domain events,
  approval records, and external sync events can reference

#### Scenario: Audit and revision both apply

- **WHEN** an action both changes product state and requires security or
  compliance audit
- **THEN** the revision must capture reconstructable state change while the
  audit record captures actor, action, result, authority basis, policy
  decision, and correlation references without duplicating full before/after
  state

#### Scenario: No state changes

- **WHEN** a sensitive authorization denial, redaction, credential access,
  context expansion denial, or export denial does not change product state
- **THEN** the system may write audit or decision records referencing the
  operation without creating revision records

### Requirement: Durable Audit Boundaries

Office Graph SHALL define which actions require durable audit records before
implementation begins.

#### Scenario: Sensitive action is performed

- **WHEN** a principal manages roles, grants, memberships, credentials,
  integrations, retention, legal hold, sensitive artifacts, external writes,
  exports, check waivers, approval gates, destructive actions, restore
  actions, or agent tool use
- **THEN** the system must create or be able to create a durable audit record
  for the action

#### Scenario: Sensitive action is denied

- **WHEN** a principal attempts a policy-sensitive action and authorization
  denies or escalates it
- **THEN** the system must create or be able to create a durable audit record
  for the denied or escalated attempt

### Requirement: Audit Record Shape

Audit records SHALL be typed and relational enough to support compliance
review, export, incident investigation, and future SIEM integration.

#### Scenario: Audit record is written

- **WHEN** a durable audit record is written
- **THEN** it must identify tenant, scope, principal, delegator when
  applicable, action, resource, result, reason when available, request source,
  request or trace identifier, operation or command identifier, related
  revision when applicable, related run, related approval, related
  integration, and timestamp

#### Scenario: Audit record references sensitive details

- **WHEN** an audit record relates to secrets, credentials, prompts, source
  code, sensitive artifacts, or restricted records
- **THEN** the audit record must preserve traceability without exposing
  sensitive payloads to principals that lack permission to view them

### Requirement: Retention Export Deletion And Legal Hold

Office Graph SHALL design governance records with retention, export, deletion,
and legal hold boundaries.

#### Scenario: Organization data export is requested

- **WHEN** an authorized export is requested for organization, workspace,
  initiative/project, audit, or governance data
- **THEN** the system must be able to determine the applicable scope,
  classifications, redactions, and excluded secret values

#### Scenario: Legal hold is active

- **WHEN** legal hold applies to records in a tenant or scope
- **THEN** deletion, purge, retention expiry, and restoration behavior must
  respect the hold according to policy

### Requirement: Audit Visibility Control

Office Graph SHALL authorize audit-log visibility separately from normal
product visibility.

#### Scenario: Auditor views audit data

- **WHEN** an auditor or admin views audit records
- **THEN** authorization must consider audit-specific capabilities, tenant and
  scope, sensitive payload references, credential references, and resource
  classification

#### Scenario: Product user views normal work

- **WHEN** a normal product user views graph items or runs
- **THEN** that visibility must not imply permission to view full audit
  records for the same resources

### Requirement: Audit Growth Planning

High-volume audit and decision-record tables SHALL identify indexing and
partitioning paths before implementation.

#### Scenario: Audit schema is designed

- **WHEN** schemas are planned for audit logs, authorization decision records,
  credential use records, model-call governance records, or external-write
  records
- **THEN** the design must include baseline tenant, scope, actor, action,
  resource, timestamp, and correlation indexes and identify whether later
  partitioning is likely
