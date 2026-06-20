## ADDED Requirements

### Requirement: Durable Audit Triggers
Office Graph SHALL create durable audit records for policy-sensitive behavior
and denied or escalated policy-sensitive attempts.

#### Scenario: Sensitive action succeeds
- **WHEN** a principal changes roles, grants, memberships, policies,
  credentials, integrations, retention, legal hold, approval gates, waivers,
  exports, external writes, destructive state, restore state, purge state, or
  sensitive agent tool use
- **THEN** Office Graph MUST create or be able to create a durable audit record
  for the action

#### Scenario: Sensitive action is denied or escalated
- **WHEN** authorization denies, redacts, escalates, or approval-gates a
  policy-sensitive action such as credential access, context expansion,
  external write, export, sensitive read, restore, purge, or waiver
- **THEN** Office Graph MUST create or be able to create a durable audit or
  authorization decision record for the attempt

### Requirement: Audit Record Shape
Office Graph audit records SHALL identify actor behavior, authority basis,
resource scope, policy result, and investigation context without copying full
revision payloads.

#### Scenario: Audit record is written
- **WHEN** a durable audit record is written
- **THEN** it MUST identify organization, applicable scope, principal,
  delegator when applicable, agent run or service account when applicable,
  action, resource or graph item when applicable, result, authority basis,
  policy bundle or decision reference when applicable, operation correlation,
  request or trace identifier, reason when available, source/origin, and
  timestamp

#### Scenario: Audit envelope is stored
- **WHEN** an audit event is persisted
- **THEN** Office Graph MUST store a typed audit event envelope with tenant,
  scope, action key, action category, result, actor/delegation context,
  operation correlation, request or trace identifiers, policy or decision
  references when applicable, source/origin context, retention class, occurred
  time, and append-only lifecycle state

#### Scenario: Audit event has affected targets
- **WHEN** an audit event affects principals, graph items, external
  references, integrations, credential metadata, policy bundles, approvals,
  runs, artifacts, or other concrete records
- **THEN** Office Graph MUST store affected targets as relational audit event
  target rows with concrete references, target role, and display or redaction
  snapshot data rather than hiding targets only in JSON details

#### Scenario: Audit event has action-specific metadata
- **WHEN** an audit action needs details that vary by action type
- **THEN** Office Graph MAY store constrained schema-versioned JSONB details
  linked to the action key and detail schema version, but MUST NOT store
  tenant, actor, action, result, target, operation, policy, retention, or
  timestamp only inside those details

#### Scenario: Audit record references sensitive data
- **WHEN** an audit record relates to secrets, credentials, prompts, source
  code, restricted artifacts, model payloads, or sensitive records
- **THEN** the audit record MUST preserve traceability through references,
  digests, classifications, or redacted summaries without exposing payloads to
  principals that lack permission to view them

### Requirement: Audit Action Registry
Office Graph SHALL register durable audit actions before emitting them.

#### Scenario: Audit action is introduced
- **WHEN** a new durable audit action such as role assignment, grant change,
  credential use, export, external write, approval, waiver, context expansion,
  legal hold, restore, purge, or agent tool use is introduced
- **THEN** the action registry MUST define action key, category, allowed actor
  kinds, allowed target kinds, result vocabulary, detail schema version,
  default retention class, default visibility, export or stream eligibility,
  and whether successful, denied, or escalated attempts are audited by default

#### Scenario: Audit action details change
- **WHEN** the details shape for an audit action changes
- **THEN** Office Graph MUST version the detail schema and preserve export and
  search compatibility for older audit events

### Requirement: Audit Event Projection
Office Graph SHALL expose customer-facing audit logs as clean event documents
projected from typed internal storage.

#### Scenario: Audit event is exported or streamed
- **WHEN** an audit event is returned through a customer-facing API, export, or
  future SIEM stream
- **THEN** Office Graph MUST project the typed envelope, targets, context,
  schema-versioned details, result, occurred time, and operation identifier
  into a stable event document while preserving authorization and redaction
  rules

#### Scenario: Audit event is searched
- **WHEN** a customer searches or filters audit logs by actor, action, target,
  result, scope, time range, operation, source, or retention class
- **THEN** Office Graph MUST satisfy those filters from typed columns or
  relational target rows rather than requiring scans over opaque details JSON

### Requirement: Audit Event Immutability And Corrections
Office Graph SHALL treat audit events as append-only records from normal
product code.

#### Scenario: Audit event needs correction
- **WHEN** an audit event needs correction, redaction, sealing, retention
  expiry, legal-hold handling, or export suppression
- **THEN** Office Graph MUST use correction, redaction, sealing, lifecycle, or
  retention records/events rather than rewriting the original audit event
  payload in place

### Requirement: Audit Visibility Is Separate
Office Graph SHALL authorize audit-log visibility separately from normal
product visibility.

#### Scenario: Product user can view a resource
- **WHEN** a user can view a graph item, run, artifact, task, or external
  reference in normal product context
- **THEN** that visibility MUST NOT automatically grant access to full audit
  records for the same resource

#### Scenario: Durable read audit applies
- **WHEN** a principal reads audit logs, secrets, credential metadata,
  sensitive artifacts, agent prompts or context, exports, legal-hold records,
  or cross-scope summaries
- **THEN** Office Graph MUST create or be able to create durable read-audit
  evidence according to organization policy and classification
