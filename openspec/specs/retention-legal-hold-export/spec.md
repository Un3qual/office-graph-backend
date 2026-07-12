# retention-legal-hold-export Specification

## Purpose
Define retention, legal-hold, and export behavior for governed records.
## Requirements
### Requirement: Retention Policy Application
Office Graph SHALL apply retention rules by organization, scope, resource kind,
sensitivity label, provider/source, and record family.

#### Scenario: Retention state is evaluated
- **WHEN** retention is evaluated for product records, revisions, audit
  records, authorization decisions, raw archives, model payloads, tool-call
  payloads, external sync events, run events, or derived renders
- **THEN** Office Graph MUST consider organization policy, workspace or
  initiative scope, sensitivity label, provider/source, record family, legal hold,
  and export obligations

#### Scenario: Default retention behavior is selected
- **WHEN** MVP retention policy is configured for product records, revisions,
  audit records, authorization decisions, raw archives, model payloads,
  tool-call payloads, external sync events, run events, derived renders, or
  tombstones
- **THEN** Office Graph MUST provide default retention classes and default
  behaviors while allowing organization policy to customize durations and
  behaviors by scope, resource kind, sensitivity label, provider/source, and
  record family, subject to legal-hold and compliance constraints

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
  resource, actor, provider/source, record family, or sensitivity label
- **THEN** Office Graph MUST block purge and retention expiry for affected
  records until the hold is released according to policy

#### Scenario: Multiple legal holds match
- **WHEN** one or more legal holds match a record by organization, workspace,
  initiative, resource, actor, provider/source, sensitivity label, or record
  family
- **THEN** Office Graph MUST apply the most restrictive matching hold and block
  purge, retention expiry, destructive redaction, and storage lifecycle expiry
  for affected records until the relevant holds are released

#### Scenario: Legal hold changes
- **WHEN** a principal creates, changes, or releases a legal hold
- **THEN** Office Graph MUST create durable audit evidence with actor,
  authority basis, scope, reason, operation correlation, and timestamp

### Requirement: Export And Redaction Boundaries
Office Graph SHALL export retained data only through authorized,
sensitivity-aware, redaction-aware workflows.

#### Scenario: Organization export is requested
- **WHEN** an authorized export is requested for organization, workspace,
  initiative, graph, audit, governance, integration, or model/tool data
- **THEN** Office Graph MUST determine included scopes, sensitivity labels,
  redactions, secret exclusions, payload references, legal holds, and audit
  visibility before producing export data

#### Scenario: Export includes sensitive references
- **WHEN** exportable records reference secrets, credentials, prompts, source
  code, sensitive artifacts, restricted graph items, or raw payload archives
- **THEN** Office Graph MUST include redacted references, digests, or approved
  payloads according to authorization and sensitivity policy

#### Scenario: Export manifest is produced
- **WHEN** an export includes product records, audit records, revisions, raw
  archives, secrets, prompts, model/tool payloads, restricted artifacts, or
  provider-derived records
- **THEN** Office Graph MUST produce a manifest identifying included scopes,
  record families, sensitivity labels, redaction decisions, excluded secrets,
  payload references, digests, raw archive references, legal-hold
  interactions, requesting principal, authorization basis, operation
  correlation, and generated artifacts

#### Scenario: Restricted payload is requested for export
- **WHEN** exportable records reference secrets, credentials, prompts,
  model/tool payloads, raw archives, restricted artifacts, or source-code-like
  content
- **THEN** Office Graph MUST export references, digests, or redacted summaries
  by default and require explicit authorization and sensitivity approval
  before exporting full payloads

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

#### Scenario: MVP partitioning posture is selected
- **WHEN** revision, audit, authorization decision, retention, legal-hold,
  export, raw archive, model/tool payload, run-event, or sync-event tables are
  modeled for MVP
- **THEN** Office Graph MUST make those tables partition-ready with tenant and
  time fields where applicable, but MUST NOT require day-one physical
  partitioning unless a later implementation change proves pre-customer volume
  or compliance requirements that justify it
