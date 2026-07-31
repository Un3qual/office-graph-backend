# soft-delete-tombstones Specification

## Purpose
Define soft deletion and durable tombstones for mutable product records.
## Requirements
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
Office Graph SHALL keep common deletion metadata on the mutable resource that
owns the lifecycle and SHALL use a domain-specific one-to-one deleted-state
resource only when richer metadata cannot reasonably live on that resource.
A generic polymorphic tombstone table keyed by resource type and resource
identifier is prohibited.

#### Scenario: Mutable record is soft-deleted
- **WHEN** a mutable owning resource is removed from normal use
- **THEN** its own table MUST preserve deletion time, deletion actor or source, operation correlation, reason when available, lifecycle state, and restore or purge eligibility

#### Scenario: Deleted record needs rich deletion state
- **WHEN** deletion needs legal-hold state, redaction status, external-provider
  reconciliation, restore-as-new linkage, purge state, or detailed rationale
  beyond the owning row's common fields
- **THEN** the owning context MUST use typed columns or a domain-specific
  related resource with a concrete foreign key

#### Scenario: Generic tombstone relationship is proposed
- **WHEN** a design proposes `resource_type` and `resource_id` polymorphism for deletion state
- **THEN** verification MUST reject it and require lifecycle ownership by the concrete resource or owning context

#### Scenario: Graph relationship is deleted
- **WHEN** a graph relationship is tombstoned
- **THEN** `graph_relationships` MUST preserve its deletion metadata directly and projections MUST derive deletion state without a generic tombstone join

### Requirement: Soft-Delete-Aware Uniqueness
Office Graph SHALL define uniqueness behavior explicitly for soft-deletable
records.

#### Scenario: Display identifier can be reused
- **WHEN** a display name, label, or non-URL user-facing identifier may be
  reused after a product record is deleted
- **THEN** Office Graph MUST enforce active-record uniqueness, such as a
  partial unique index that excludes deleted rows, while preserving deleted
  history

#### Scenario: URL-bearing slug is deleted
- **WHEN** a URL-bearing slug or handle has ever identified a resource within
  an organization and scope
- **THEN** Office Graph MUST keep the slug or handle reserved after soft
  deletion so a new generated slug that would collide with `foo` becomes
  `foo-1`, then `foo-2`, and so on, and the old URL MUST NOT resolve to a
  different new resource

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
- **THEN** Office Graph MUST check authorization, scope, sensitivity label,
  retention state, legal hold, uniqueness conflicts, external-provider state,
  and operation correlation before restoring in place or restoring as a new
  linked active record

#### Scenario: Restore mode is selected
- **WHEN** a native deleted record is restored and its original scope, URL slug
  or handle reservation, and parent/container relationships remain available
- **THEN** Office Graph SHOULD restore the record in place, while imported,
  provider-backed, externally moved, or active-uniqueness-conflicted records
  MUST restore as a new linked active record or require an explicit rename or
  remap decision

#### Scenario: Deleted record is purged
- **WHEN** a principal, retention job, or legal workflow attempts to purge a
  deleted record or payload
- **THEN** Office Graph MUST honor legal hold, retention policy, audit
  requirements, export obligations, external-provider contracts, and minimal
  tombstone or digest retention before removing durable data

### Requirement: Edge Tombstones And Restore Cascade
Office Graph SHALL define graph relationship lifecycle behavior when graph
items or work containers are deleted or restored.

#### Scenario: Graph item is deleted
- **WHEN** a graph item is deleted or tombstoned
- **THEN** Office Graph MUST tombstone, disable, or preserve each incident edge
  according to relationship type so projections do not expose dangling or
  misleading relationships

#### Scenario: Graph item is restored
- **WHEN** a graph item is restored
- **THEN** Office Graph MUST NOT automatically restore all incident edges
  unless the relationship type declares restore eligibility and policy approves
  the restore

#### Scenario: Parent work container is restored
- **WHEN** a deleted parent work container is restored
- **THEN** Office Graph MUST declare whether child graph items restore in
  place, remain deleted, or require explicit selection before they become
  active again
