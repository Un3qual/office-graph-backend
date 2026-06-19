## ADDED Requirements

### Requirement: Soft Deletion For Mutable Product Records
Office Graph SHALL remove mutable product records from normal use through
soft-deleted or tombstoned lifecycle state rather than ordinary hard deletion.

#### Scenario: Mutable record is deleted
- **WHEN** a graph item, work container, task, requirement, decision, check,
  evidence item, artifact, conversation, review finding, provider-neutral
  product record, or other mutable product record is deleted
- **THEN** Office Graph MUST preserve deletion actor, operation correlation,
  deletion time, reason when available, lifecycle state, and restore or purge
  eligibility

#### Scenario: Append-only record is removed from product views
- **WHEN** an audit record, authorization decision, raw archive, run event,
  external sync event, or immutable revision record should no longer appear in
  ordinary product views
- **THEN** Office Graph MUST use retention, redaction, sealing, export, or
  purge workflows rather than normal product soft deletion

### Requirement: Tombstone Metadata
Office Graph SHALL use tombstones when deletion needs metadata beyond simple
deleted columns.

#### Scenario: Deleted record needs rich deletion state
- **WHEN** deletion needs legal-hold state, redaction status, external-provider
  reconciliation, restore-as-new linkage, purge state, or detailed deletion
  rationale
- **THEN** Office Graph MUST preserve a tombstone or domain-specific deleted
  state with concrete references to the deleted resource and operation

### Requirement: Soft-Delete-Aware Uniqueness
Office Graph SHALL define uniqueness behavior explicitly for soft-deletable
records.

#### Scenario: User-facing identifier can be reused
- **WHEN** a name, slug, label, or user-facing identifier may be reused after a
  product record is deleted
- **THEN** Office Graph MUST enforce active-record uniqueness, such as a
  partial unique index that excludes deleted rows, while preserving deleted
  history

#### Scenario: Provider identifier is retained
- **WHEN** a provider external identifier is stored for reconciliation
- **THEN** Office Graph MUST generally preserve uniqueness per organization,
  external source, object type, and external identifier even when the local
  product record is deleted

### Requirement: Restore And Purge Workflows
Office Graph SHALL treat restore and purge as policy-controlled domain
workflows.

#### Scenario: Deleted record is restored
- **WHEN** a principal attempts to restore a deleted record
- **THEN** Office Graph MUST check authorization, scope, classification,
  retention state, legal hold, uniqueness conflicts, external-provider state,
  and operation correlation before restoring in place or restoring as a new
  linked active record

#### Scenario: Deleted record is purged
- **WHEN** a principal, retention job, or legal workflow attempts to purge a
  deleted record or payload
- **THEN** Office Graph MUST honor legal hold, retention policy, audit
  requirements, export obligations, external-provider contracts, and minimal
  tombstone or digest retention before removing durable data
