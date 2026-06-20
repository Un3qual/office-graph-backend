## ADDED Requirements

### Requirement: Retention Policy Application
Office Graph SHALL apply retention rules by organization, scope, resource kind,
classification, provider/source, and record family.

#### Scenario: Retention state is evaluated
- **WHEN** retention is evaluated for product records, revisions, audit
  records, authorization decisions, raw archives, model payloads, tool-call
  payloads, external sync events, run events, or derived renders
- **THEN** Office Graph MUST consider organization policy, workspace or
  initiative scope, classification, provider/source, record family, legal hold,
  and export obligations

#### Scenario: Retention expires
- **WHEN** a record reaches retention expiry
- **THEN** Office Graph MUST execute a policy-controlled expiry, redaction,
  sealing, archive-tiering, or purge workflow rather than deleting data through
  ordinary product actions

### Requirement: Legal Hold
Office Graph SHALL preserve records subject to legal hold and audit legal-hold
lifecycle changes.

#### Scenario: Legal hold applies
- **WHEN** legal hold applies to an organization, workspace, initiative,
  resource, actor, provider/source, record family, or classification
- **THEN** Office Graph MUST block purge and retention expiry for affected
  records until the hold is released according to policy

#### Scenario: Legal hold changes
- **WHEN** a principal creates, changes, or releases a legal hold
- **THEN** Office Graph MUST create durable audit evidence with actor,
  authority basis, scope, reason, operation correlation, and timestamp

### Requirement: Export And Redaction Boundaries
Office Graph SHALL export retained data only through authorized,
classification-aware, redaction-aware workflows.

#### Scenario: Organization export is requested
- **WHEN** an authorized export is requested for organization, workspace,
  initiative, graph, audit, governance, integration, or model/tool data
- **THEN** Office Graph MUST determine included scopes, classifications,
  redactions, secret exclusions, payload references, legal holds, and audit
  visibility before producing export data

#### Scenario: Export includes sensitive references
- **WHEN** exportable records reference secrets, credentials, prompts, source
  code, sensitive artifacts, restricted graph items, or raw payload archives
- **THEN** Office Graph MUST include redacted references, digests, or approved
  payloads according to authorization and classification policy

### Requirement: Retention Growth Planning
Office Graph SHALL design retained record families for high-volume indexing and
future partitioning.

#### Scenario: High-volume retained table is designed
- **WHEN** audit logs, authorization decisions, revisions, raw archives, model
  calls, tool calls, run events, sync events, or observability events are
  modeled
- **THEN** Office Graph MUST include tenant, scope or resource, actor or
  source, action or kind, operation, timestamp, lifecycle or retention state,
  and partition-ready fields where applicable

#### Scenario: Audit log retention is planned
- **WHEN** audit event, audit event target, audit event detail, or audit action
  registry tables are modeled
- **THEN** Office Graph MUST include retention class, export or stream
  eligibility, redaction state, legal-hold interactions, and partition-ready
  time/tenant fields where applicable
