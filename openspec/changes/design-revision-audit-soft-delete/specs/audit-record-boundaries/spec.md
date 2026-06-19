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

#### Scenario: Audit record references sensitive data
- **WHEN** an audit record relates to secrets, credentials, prompts, source
  code, restricted artifacts, model payloads, or sensitive records
- **THEN** the audit record MUST preserve traceability through references,
  digests, classifications, or redacted summaries without exposing payloads to
  principals that lack permission to view them

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
